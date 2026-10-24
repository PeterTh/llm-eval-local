# frozen_string_literal: true
require "json"
require "fileutils"
require "digest"
require "time"
$stdout.sync = true
$stderr.sync = true

evidence = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/amendments/20261023-filesystem-isolation/evaluation"
plan = JSON.parse(File.read(File.join(evidence, "campaign.json")))
scratch = plan.fetch("scratch_root")
validation = plan.fetch("validation_run")
source = plan.fetch("isolated_source_checkout")
primary = "/home/petert/llm_timing_audit/20261024-deepseek41-opencode-isolated"
boundary = "#{primary}-qtclustering"
priority = "#{primary}-priority"
adjudication = "#{primary}-sol61"
require File.join(scratch, "experiment/tools/timing_audit/bin/timing_priority_review")
require File.join(scratch, "experiment/tools/timing_audit/bin/timing_finalize_audit")
require File.join(scratch, "experiment/tools/timing_audit/lib/qtclustering_boundary")
phase = "verify_validation"
checkpoint = lambda do |extra = {}|
  report = { "checked_at" => Time.now.utc.iso8601, "phase" => phase,
    "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest, "primary" => primary,
    "qtclustering" => boundary, "review_policy" => QtclusteringBoundary::REVIEW_POLICY }.merge(extra)
  TimingAudit.atomic_write(File.join(evidence, "timing-review-progress.json"), JSON.pretty_generate(report) + "\n")
  puts JSON.generate(report)
end
begin
  checkpoint.call
  manifest = LocalEvaluation::Manifest.new(validation)
  manifest.verify_input_revisions!
  completion = JSON.parse(File.read(File.join(evidence, "validation-completion-review.json")))
  raise "Unexpected validation source or scope" unless completion.fetch("completed") == 24 && manifest.runs.keys.sort == plan.fetch("affected_observations").sort &&
    completion.fetch("source_commit") == plan.fetch("original_source_commit") &&
    completion.fetch("validation_results_sha256") == TimingAudit.sha256_file(File.join(validation, "validation/all_validation_results.yaml"))
  native = LocalEvaluation::ValidationPipeline.new(run_dir: validation).send(:load_results)
  expected_mpi = native.values.select { |r| r.output_comparison && %w[mpi hybrid].include?(r.par_type) }.map(&:id_string).sort
  expected_qt = native.values.select { |r| r.output_comparison && r.benchmark == "qtclustering" }.map(&:id_string).sort
  raise "Review scope is unexpectedly empty" if expected_mpi.empty?
  context = File.join(validation, "timing-platform-context.txt")
  roots = {}
  phase = "primary_luna"
  checkpoint.call("programs" => expected_mpi.size)
  TimingAudit::InventoryBuilder.new(validation_run: validation, source_root: source, output_dir: primary, trial_size: 16).run unless File.exist?(primary)
  inventory = TimingAudit.load_jsonl(File.join(primary, "inventory.jsonl"))
  raise "MPI/hybrid review selection differs" unless inventory.map { |r| r.fetch("id") }.sort == expected_mpi
  TimingAudit::AuditRunner.new(output_dir: primary, scope: "full", jobs: 4, model: "gpt-5.6-luna", effort: "high").run
  roots[primary] = ["gpt-5.6-luna", "high"]
  phase = "independent_luna"
  checkpoint.call
  TimingPriorityReview.prepare(main_root: primary, output_dir: priority) unless File.exist?(priority)
  TimingPriorityReview.run(output_dir: priority, jobs: 4)
  TimingAudit::AuditVerifier.new(priority, "full").run
  roots[priority] = ["gpt-5.6-luna", "high"]
  phase = "uncertainty_only_sol61"
  checkpoint.call
  TimingPriorityReview.prepare_adjudication(main_root: primary, review_root: priority,
    output_dir: adjudication, context_path: context, model: "gpt-6.1-sol") unless File.exist?(adjudication)
  TimingAudit::AuditRunner.new(output_dir: adjudication, scope: "full", jobs: 2, model: "gpt-6.1-sol", effort: "xhigh").run
  roots[adjudication] = ["gpt-6.1-sol", "xhigh"]
  phase = "finalize_mpi_hybrid"
  checkpoint.call
  TimingFinalizeAudit.run(main_root: primary, priority_root: priority, adjudication_root: adjudication) unless File.directory?(File.join(primary, "final"))
  decision_roots = [primary]
  unless expected_qt.empty?
    phase = "qtclustering_luna"
    checkpoint.call("programs" => expected_qt.size)
    QtclusteringBoundary::Builder.new(release_root: "/home/petert/llm-eval-local", validation_runs: [validation], include_release: false,
      source_root: source, source_commit: plan.fetch("original_source_commit"),
      reference_root: plan.fetch("frozen_reference_checkout"), reference_commit: plan.fetch("reference_source_commit"),
      benchmark_config: plan.fetch("inherited_benchmark_configuration"), context_path: context,
      output_dir: boundary, trial_size: 16).run unless File.exist?(boundary)
    raise "QT selection differs" unless TimingAudit.load_jsonl(File.join(boundary, "inventory.jsonl")).map { |r| r.fetch("id") }.sort == expected_qt
    TimingAudit::AuditRunner.new(output_dir: boundary, scope: "full", jobs: 4, model: "gpt-5.6-luna", effort: "high").run
    roots[boundary] = ["gpt-5.6-luna", "high"]
    phase = "qt_uncertainty_only_sol61"
    checkpoint.call
    QtclusteringBoundary.run_review(main_root: boundary, output_dir: "#{boundary}-sol61", scope: "full", jobs: 2)
    roots["#{boundary}-sol61"] = ["gpt-6.1-sol", "xhigh"]
    QtclusteringBoundary.finalize(main_root: boundary, review_root: "#{boundary}-sol61") unless File.directory?(File.join(boundary, "final"))
    decision_roots << boundary
  end
  phase = "verify_final_review"
  checkpoint.call
  reviews = roots.map do |root, (model, effort)|
    TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: model, effort: effort)
    verifier = TimingAudit::AuditVerifier.new(root, "full")
    # The QT adjudication inventory covers every QT candidate, but only the
    # uncertainty/disagreement subset is sent to Sol. Do not demand blanket
    # adjudication for confident Luna results.
    verifier.run unless root == "#{boundary}-sol61"
    paths = Dir[File.join(root, "results/*.json")]
    paths.each do |path|
      row = JSON.parse(File.read(path))
      id = row.fetch("program_id")
      verifier.verify_result!(id, row)
      accepted = Dir[File.join(root, "logs", id, "attempt-*/metadata.yaml")].filter_map do |metadata|
        data = YAML.safe_load_file(metadata)
        data if data["result_sha256"] == TimingAudit.sha256_file(path)
      end
      raise "Wrong reviewer or unsafe attempt: #{id}" unless !accepted.empty? && accepted.all? { |r| r["model"] == model && r["reasoning_effort"] == effort && r["static_only_verified"] == true }
    end
    Dir[File.join(root, "logs/**/events.jsonl")].each do |path|
      File.foreach(path) do |line|
        item = JSON.parse(line)["item"]
        raise "Prohibited reviewer tool event" if item && !%w[agent_message reasoning error].include?(item["type"])
      end
    end
    { "root" => root, "model" => model, "effort" => effort, "responses" => paths.size, "prohibited_tool_events" => 0 }
  end
  decisions = {}
  decision_roots.each do |root|
    TimingAudit.load_jsonl(File.join(root, "final/decisions.jsonl")).each do |row|
      id = row.fetch("program_id")
      raise "Overlay source mismatch" if decisions[id] && decisions[id].fetch("source_digest") != row.fetch("source_digest")
      decisions[id] = row
    end
  end
  raise "Combined review scope differs" unless decisions.keys.sort == (expected_mpi | expected_qt).sort
  unresolved = decisions.values.select { |r| r["final_verdict"] == "ambiguous" || r["final_confidence"] != "high" || (r["final_verdict"] == "invalid" && !r["timing_only_fix_possible"]) }
  report = { "checked_at" => Time.now.utc.iso8601, "passed" => unresolved.empty?, "unique_programs" => decisions.size,
    "verdicts" => decisions.values.map { |r| r.fetch("final_verdict") }.tally, "reviews" => reviews,
    "unresolved" => unresolved, "source_only" => true, "source_commit" => plan.fetch("original_source_commit"),
    "review_policy" => QtclusteringBoundary::REVIEW_POLICY,
    "retained_observations_reviewed_again" => 0 }
  TimingAudit.atomic_write(File.join(evidence, "audit-completion-review.json"), JSON.pretty_generate(report) + "\n")
  phase = unresolved.empty? ? "timing_correction_next" : "unresolved_scientific_review"
  checkpoint.call("unique_programs" => decisions.size, "verdicts" => report.fetch("verdicts"), "unresolved" => unresolved.size)
rescue Exception => error
  stopped = phase
  phase = "needs_review"
  checkpoint.call("stopped_phase" => stopped, "error" => "#{error.class}: #{error.message}")
  raise
end
