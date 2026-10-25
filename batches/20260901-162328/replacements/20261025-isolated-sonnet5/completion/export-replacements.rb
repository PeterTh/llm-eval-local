# frozen_string_literal: true
require_relative "experiment/tools/timing_audit/bin/export_validation_audit"
require_relative "benchmark-export"
require_relative "release/tools/current_release"
require "open3"

scratch = __dir__
root = File.join(scratch, "release")
campaign = "/home/petert/llm_para_campaigns/20261025-143725-sonnet5-isolated-replacements"
evidence = File.join(campaign, "evaluation")
plan = JSON.parse(File.read(File.join(evidence, "campaign.json")))
native = plan.fetch("validation_run")
audit = "/home/petert/llm_timing_audit/20261025-sonnet5-isolated"
fixes = "/home/petert/llm_timing_fixes/20261025-sonnet5-isolated"
base = "batches/20260901-162328/replacements/20261025-isolated-sonnet5"
batch = File.join(root, base)
ids = plan.fetch("affected_observations").sort
raise "Wrong scope" unless ids.size == 7 && ids.all? { |id| id.include?("_claude-sonnet-5-cc-medium_") }
completion = JSON.parse(File.read(File.join(evidence, "benchmark-completion-review.json")))
raise "Unverified benchmark completion" unless completion.fetch("verification") == "passed" && completion.fetch("completed") == 6 && completion.fetch("all_records_reconciled")
stage = ARGV.fetch(0, "all")
raise "Unknown export stage" unless %w[all validation corrections benchmark complete].include?(stage)
copy = lambda do |source, relative|
  TimingAudit.atomic_write(File.join(batch, relative), File.binread(source))
end
json = ->(relative, value) { TimingAudit.atomic_write(File.join(batch, relative), JSON.pretty_generate(value) + "\n") }
selected = lambda do |source, relative, names|
  names.each { |name| copy.call(File.join(source, name), File.join(relative, name)) if File.file?(File.join(source, name)) }
end

if %w[all validation].include?(stage)
  ValidationAuditExport.run(run_dir: native, output_dir: batch, primary: audit, priority: "#{audit}-priority", adjudication: "#{audit}-sol61")
  { "primary" => audit, "priority" => "#{audit}-priority", "adjudication" => "#{audit}-sol61" }.each do |label, source|
    selected.call(source, "timing-audit/#{label}", %w[pilot-review.json operational-provenance.json static-evidence-snapshot.rb
      review-policy-snapshot.rb active-review-policy-full.rb adjudication-plan-full.json adjudication-selection.jsonl])
  end
  decisions_path = "timing-audit/primary/final/decisions.jsonl"
  decisions = TimingAudit.load_jsonl(File.join(batch, decisions_path))
  expected = TimingAudit.load_jsonl(File.join(batch, "validation/records.jsonl")).select do |r|
    LocalEvalArtifact::VALIDATION_STAGES.all? { |name| r.fetch("metadata").fetch("stages").fetch(name) }
  end.map { |r| r.fetch("id") }.sort
  raise "Timing audit coverage changed" unless expected.size == 6 && decisions.map { |r| r.fetch("program_id") }.sort == expected
  raise "Unresolved audit" unless decisions.all? { |r| r.fetch("final_confidence") == "high" && !r.fetch("timing_review_required") }
  counts = decisions.group_by { |r| r.fetch("final_verdict") }.transform_values(&:size)
  raise "Unexpected verdicts" unless counts == { "valid" => 4, "invalid" => 2 }
  json.call("timing-audit/resolved-selection.json", { "schema_version" => 1,
    "source_commit" => plan.fetch("original_source_commit"), "record_count" => decisions.size,
    "ordered_decisions" => [{ "path" => decisions_path, "sha256" => TimingAudit.sha256_file(File.join(batch, decisions_path)) }],
    "verdict_counts" => counts, "correction_ids" => decisions.select { |r| r.fetch("timing_fix_required") }.map { |r| r.fetch("program_id") }.sort,
    "policy" => "Review all six passing MPI/hybrid replacements statically. Luna first; Sol 6.1 only for uncertainty or disagreement. No QT candidates." })
  TimingAudit.atomic_write(File.join(batch, "timing-audit/conditional-decisions.jsonl"), "")
  summary = JSON.parse(File.read(File.join(batch, "summary.json")))
  summary.merge!("timing_audit_selection" => "timing-audit/resolved-selection.json", "unique_timing_audited_programs" => 6,
    "timing_audit_final_verdicts" => counts)
  json.call("summary.json", summary)
end
if %w[all corrections].include?(stage)
  TimingCorrectionExport.run(batch_dir: batch, proposal_root: "#{fixes}-proposals", review_root: "#{fixes}-review",
    adjudication_root: "#{fixes}-review-sol61", final_root: "#{fixes}-final",
    validation_run: "/home/petert/llm_para_local_evaluation/20261025-sonnet5-isolated-corrected",
    original_source: File.join(scratch, "original-backup"), audit_selection: File.join(batch, "timing-audit/resolved-selection.json"))
end
if %w[all benchmark].include?(stage)
  BenchmarkBatchExport.run(run_dir: native, batch_dir: batch, conditional_decisions: File.join(batch, "timing-audit/conditional-decisions.jsonl"))
end
if %w[all complete].include?(stage)
  raise "Native aggregate failed" unless system(RbConfig.ruby, File.join(scratch, "local-evaluation-driver.rb"), "aggregate", "--run-dir=#{native}")
  raise "Aggregate import failed" unless system(RbConfig.ruby, File.join(root, "tools/import_batch_aggregate.rb"), "--native-run=#{native}", "--batch=20260901-162328", "--evidence-root=#{base}")
  selected.call(campaign, "generation", %w[campaign.json run-ids.txt completion.json launch.json preflight-review.json
    infrastructure-preflight.json isolation-preflight-2.1.252.json isolation-preflight-2.1.269.json
    original-observations.json audited-findings.json superseded-files.json unchanged-files.json
    legacy-permission-repair.json resume-after-permission-repair.json regression-tests.log timing-template-reuse.json])
  selected.call(campaign, "generation/supervision", %w[prepare.rb run.rb controller.rb launch.rb preflight.rb repair_legacy_permissions.rb validate-replacements.rb])
  Dir[File.join(campaign, "release-verification/*")].sort.each do |path|
    raise "Unexpected CLI verification artifact" unless File.file?(path) && File.size(path) < 200_000
    copy.call(path, "generation/release-verification/#{File.basename(path)}")
  end
  manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
  reusable = {}
  LocalEvalArtifact.regular_files(root).each do |path|
    relative = LocalEvalArtifact.relative_path(root, path)
    next unless relative.start_with?("method/") || relative.include?("/method/")
    reusable[LocalEvalArtifact.sha256(path)] ||= relative
  end
  layout = manifest.fetch("files").to_h do |name, digest|
    source = File.join(campaign, "method", name)
    raise "Frozen generation method changed: #{name}" unless LocalEvalArtifact.sha256(source) == digest
    relative = reusable[digest]
    unless relative
      stored = "generation/method/#{name.gsub('/bin/', '/commands/')}"
      copy.call(source, stored)
      relative = "#{base}/#{stored}"
      reusable[digest] = relative
    end
    [name, relative]
  end
  json.call("generation/method-layout.json", layout)
  observations = Dir[File.join(campaign, "observations/*.json")].sort.map { |p| JSON.parse(File.read(p)) }
  raise "Generation scope changed" unless observations.map { |r| r.fetch("id") }.sort == ids
  observations.each do |observation|
    id = observation.fetch("id")
    raise "Unexpected generation identity/outcome" unless observation.fetch("model") == "claude-sonnet-5" &&
      observation.fetch("version") == manifest.fetch("observation_versions").fetch(id) && observation.fetch("outcome") == "completed" && observation.fetch("retry_count").zero?
    isolation = observation.fetch("filesystem_isolation")
    raise "Isolation differs" unless isolation.fetch("policy") == manifest.fetch("generation_filesystem_policy") &&
      isolation.fetch("implementation_sha256") == manifest.fetch("files").fetch("lib/generation_filesystem.rb") &&
      isolation.fetch("preflight") == { "passed" => true, "operator_home_visible" => false, "other_observations_visible" => false }
    observation.fetch("sha256").each do |name, digest|
      bytes, error, status = Open3.capture3("git", "-C", "/home/petert/llm_para_experiments", "show", "#{plan.fetch('original_source_commit')}:20260901-162328/#{id}/#{name}")
      raise "Retained generation metadata changed: #{id}/#{name}: #{error}" unless status.success? && Digest::SHA256.hexdigest(bytes) == digest
    end
  end
  TimingAudit.atomic_write(File.join(batch, "generation/observations.jsonl"), TimingAudit.dump_jsonl(observations))
  rows = CSV.read(File.join(batch, "aggregate/aggregate_results.csv"), headers: true).to_h { |r| [CurrentRelease.id(r), r] }
  CurrentRelease.new(root).verify_generation_observations!({ "id" => "20260901-162328" }, observations, rows)
  cleanups = Dir[File.join(campaign, "cleanup/*.json")].sort.map { |p| JSON.parse(File.read(p)) }
  raise "Cleanup scope differs" unless cleanups.map { |r| r.fetch("id") }.sort == ids && cleanups.all? { |r| r.fetch("verified_empty") }
  TimingAudit.atomic_write(File.join(batch, "generation/cleanup.jsonl"), TimingAudit.dump_jsonl(cleanups))
  selected.call(evidence, "completion", %w[campaign.json validation-completion-review.json audit-completion-review.json timing-review-progress.json
    timing-review-driver.rb timing-path-repair.json correction-policy.json correction-full-progress.json correction-commit.json
    revalidation-completion-review.json source-correction-push.json benchmark-canary-gate.json benchmark-completion-review.json
    followup-template-reuse.json correction-template-reuse.json benchmark-template-reuse.json export-template-reuse.json
    correction-driver.rb commit-corrections.rb revalidation-driver.rb verify-revalidation-completion.rb
    canary-driver.rb benchmark-driver.rb verify-benchmark-records.rb launch-stage.rb])
  copy.call(__FILE__, "completion/export-replacements.rb")
  receipt = { "exported_at" => Time.now.utc.iso8601, "batch" => "20260901-162328", "records" => 7,
    "benchmarks" => 6, "successful" => completion.fetch("successful"), "corrections" => 2,
    "evidence_root" => base, "release_workspace" => root,
    "source_commit" => plan.fetch("original_source_commit"),
    "corrected_source_commit" => JSON.parse(File.read(File.join(evidence, "correction-commit.json"))).fetch("corrected_commit"),
    "driver_sha256" => TimingAudit.sha256_file(__FILE__),
    "benchmark_completion_sha256" => TimingAudit.sha256_file(File.join(evidence, "benchmark-completion-review.json")) }
  TimingAudit.atomic_write(File.join(evidence, "batch-export.json"), JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, File.join(evidence, File.basename(__FILE__)))
  puts JSON.pretty_generate(receipt)
end
