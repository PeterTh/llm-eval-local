# frozen_string_literal: true
$stdout.sync = true
require_relative "experiment/tools/timing_audit/lib/timing_fix_revision"
require_relative "experiment/tools/timing_audit/lib/timing_fix_materializer"
require_relative "experiment/tools/timing_audit/lib/timing_fix_adjudication"
require_relative "reuse-unchanged-correction-reviews"

campaign = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation"
base = "/home/petert/llm_timing_fixes/20261107-fable51-medium"
old = { "proposals" => "#{base}-proposals", "review" => "#{base}-review", "adjudication" => "#{base}-review-sol61" }
current = { "proposals" => "#{base}-proposals-revision1", "review" => "#{base}-review-revision1", "adjudication" => "#{base}-review-revision1-sol61" }
id = "roomsim_claude-fable-5.1-cc-medium_hybrid_r2"
preserved_nonaccept_ids = ["cahn-hilliard_claude-fable-5.1-cc-medium_hybrid_r1"]
phase = "verify_prior_decision"
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "correction-revision-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  raise "Revision already exists" if current.values.any? { |root| File.exist?(root) }
  progress = JSON.parse(File.read(File.join(campaign, "correction-full-progress.json")))
  raise "Unexpected unresolved selection" unless progress.fetch("phase") == "awaiting_correction_commit_review" && progress.fetch("unresolved_ids").empty?
  scope_path = File.join(campaign, "correction-full-operator-scope-review.json")
  scope_review = JSON.parse(File.read(scope_path))
  raise "Unexpected operator scope review" unless scope_review.fetch("status") == "one_proposal_requires_scope_revision" &&
    scope_review.fetch("program_id") == id && scope_review.fetch("patch_sha256") == TimingAudit.sha256_file(File.join(old.fetch("proposals"), "materialized/timing-fixes-full.patch"))
  prior_proposal_path = File.join(old.fetch("proposals"), "proposals", "#{id}.json")
  prior_review_path = File.join(old.fetch("review"), "results", "#{id}.json")
  prior_proposal = JSON.parse(File.read(prior_proposal_path))
  prior_review = JSON.parse(File.read(prior_review_path))
  raise "Operator proposal binding changed" unless scope_review.fetch("prior_proposal_sha256") == TimingAudit.sha256_file(prior_proposal_path)
  raise "Unexpected prior Roomsim review" unless prior_review.fetch("verdict") == "accept" && prior_review.fetch("confidence") == "high"
  TimingFix::ProposalVerifier.new(old.fetch("proposals"), "full").run
  TimingFixReview::Verifier.new(old.fetch("review"), "full").run
  TimingFixAdjudication::Verifier.new(old.fetch("adjudication"), "full").run
  fingerprints = old.values.flat_map { |root| Dir[File.join(root, "**", "*")].select { |path| File.file?(path) } }.sort.to_h do |path|
    raise "Symlink in retained evidence" if File.symlink?(path)
    [path, TimingAudit.sha256_file(path)]
  end
  inventory = TimingAudit.load_jsonl(File.join(old.fetch("proposals"), "inventory.jsonl"))
  ids = inventory.map { |row| row.fetch("id") }.sort
  raise "Unexpected correction inventory" unless ids.size == 69 && ids.include?(id)
  unchanged_ids = ids - [id]
  accepted = TimingAudit.load_jsonl(File.join(old.fetch("review"), "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
  nonaccept = unchanged_ids.reject { |key| accepted.fetch(key).fetch("verdict") == "accept" && accepted.fetch(key).fetch("confidence") == "high" }
  raise "Unexpected nonaccepting review selection" unless nonaccept == preserved_nonaccept_ids
  prior_adjudications = TimingAudit.load_jsonl(File.join(old.fetch("adjudication"), "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
  raise "Unresolved prior adjudication" unless prior_adjudications.keys.sort == preserved_nonaccept_ids && prior_adjudications.values.all? { |row| row.fetch("final_verdict") == "accept" && row.fetch("confidence") == "high" }
  feedback_text = "The operator's complete-diff scope review found this unnecessary work-placement change despite the prior Luna acceptance. " +
    scope_review.fetch("finding") + "\nRequired minimal correction: " + scope_review.fetch("required_revision") +
    "\nKeep the algorithm, arithmetic, workload, result output and validation unchanged. Return a complete timing-only replacement proposal against the original source."
  feedback = [{ "program_id" => id, "prior_proposal_sha256" => TimingAudit.sha256_file(prior_proposal_path), "feedback" => feedback_text }]
  feedback_path = File.join(campaign, "correction-revision-feedback.json")
  raise "Feedback already exists" if File.exist?(feedback_path)
  TimingAudit.atomic_write(feedback_path, JSON.pretty_generate(feedback) + "\n")
  FileUtils.cp_r(old.fetch("proposals"), current.fetch("proposals"))
  fingerprints.each do |path, digest|
    next unless path.start_with?(old.fetch("proposals") + "/")
    copied = current.fetch("proposals") + path.delete_prefix(old.fetch("proposals"))
    raise "Proposal clone differs" unless TimingAudit.sha256_file(copied) == digest
  end
  phase = "revise_single_proposal"
  checkpoint.call
  TimingFixRevision::Runner.new(output_dir: current.fetch("proposals"), scope: "full", jobs: 1,
    model: "gpt-6.1-sol", effort: "high", feedback_path: feedback_path).run
  TimingFix::ProposalVerifier.new(current.fetch("proposals"), "full").run
  unchanged_ids.each do |key|
    relative = File.join("proposals", "#{key}.json")
    raise "Unrelated proposal changed" unless TimingAudit.sha256_file(File.join(old.fetch("proposals"), relative)) == TimingAudit.sha256_file(File.join(current.fetch("proposals"), relative))
  end
  phase = "compile_revised_sources"
  checkpoint.call
  TimingFixMaterializer.run(output_dir: current.fetch("proposals"), scope: "full", jobs: 4)
  phase = "reuse_unchanged_reviews"
  checkpoint.call
  TimingFixReview::InventoryBuilder.new(proposal_root: current.fetch("proposals"), output_dir: current.fetch("review"), scope: "full").run
  TimingFixReviewReuse.run(source: old.fetch("review"), destination: current.fetch("review"), model: "gpt-5.6-luna", effort: "high", only_ids: unchanged_ids,
    preserve_nonaccept_ids: preserved_nonaccept_ids)
  phase = "independent_revised_review"
  checkpoint.call
  TimingFixReview::Runner.new(output_dir: current.fetch("review"), scope: "full", jobs: 1, model: "gpt-5.6-luna", effort: "high").run
  phase = "targeted_revised_adjudication"
  checkpoint.call
  TimingFixAdjudication::InventoryBuilder.new(review_root: current.fetch("review"), output_dir: current.fetch("adjudication")).run
  TimingFixAdjudication::Runner.new(output_dir: current.fetch("adjudication"), scope: "full", jobs: 1, model: "gpt-6.1-sol", effort: "xhigh").run
  reviews = TimingAudit.load_jsonl(File.join(current.fetch("review"), "summary-full.jsonl"))
  adjudications = TimingAudit.load_jsonl(File.join(current.fetch("adjudication"), "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
  unresolved = reviews.reject do |row|
    selected = adjudications[row.fetch("program_id")] || row
    (selected["final_verdict"] || selected.fetch("verdict")) == "accept" && selected.fetch("confidence") == "high"
  end.map { |row| row.fetch("program_id") }
  fingerprints.each { |path, digest| raise "Prior evidence changed: #{path}" unless TimingAudit.sha256_file(path) == digest }
  raise "Revised proposal still unresolved: #{unresolved.join(', ')}" unless unresolved.empty?
  raise "Review coverage changed" unless reviews.map { |row| row.fetch("program_id") }.sort == ids
  record = {
    "schema_version" => 1, "completed_at" => TimingAudit.utc_now, "passed" => true,
    "program_id" => id, "prior_roots" => old, "evidence_roots" => current,
    "prior_proposal_sha256" => TimingAudit.sha256_file(prior_proposal_path), "prior_proposal" => prior_proposal,
    "prior_independent_review_sha256" => TimingAudit.sha256_file(prior_review_path), "prior_independent_review" => prior_review,
    "revision_trigger" => "operator timing-only scope review; prior Luna acceptance is retained unchanged",
    "operator_scope_review_sha256" => TimingAudit.sha256_file(scope_path), "operator_scope_review" => scope_review,
    "feedback" => feedback, "feedback_sha256" => TimingAudit.sha256_file(feedback_path),
    "revised_proposal_sha256" => TimingAudit.sha256_file(File.join(current.fetch("proposals"), "proposals", "#{id}.json")),
    "accepted_review_sha256" => TimingAudit.sha256_file(File.join(current.fetch("review"), "results", "#{id}.json")),
    "prior_evidence_files" => fingerprints.size, "prior_evidence_unchanged" => true,
    "prior_evidence_tree_sha256" => Digest::SHA256.hexdigest(JSON.generate(fingerprints)),
    "unchanged_proposals" => unchanged_ids.size, "reused_independent_reviews" => unchanged_ids.size,
    "new_independent_reviews" => 1, "new_adjudications" => adjudications.size, "accepted_corrections" => ids.size,
    "preserved_nonaccept_review_ids" => preserved_nonaccept_ids,
    "reuse_receipt_sha256" => TimingAudit.sha256_file(File.join(current.fetch("review"), "reused-reviews.json")),
    "driver_sha256" => TimingAudit.sha256_file(__FILE__),
    "reuse_helper_sha256" => TimingAudit.sha256_file(File.join(__dir__, "reuse-unchanged-correction-reviews.rb")),
    "policy" => "Only the operator-flagged Roomsim timing proposal is revised and freshly reviewed. The other 68 proposals and literal-prompt-bound reviews are reused unchanged, including the Cahn-Hilliard Luna rejection. Only nonaccepting/uncertain reviews receive Sol adjudication; Cahn-Hilliard receives a fresh decision because the global compiled-patch evidence in that prompt has changed. Every earlier attempt and decision remains intact; no program execution or scientific observation was repeated."
  }
  TimingAudit.atomic_write(File.join(campaign, "correction-revision-1.json"), JSON.pretty_generate(record) + "\n")
  phase = "awaiting_correction_commit_review"
  checkpoint.call("unresolved_ids" => [], "evidence_roots" => current, "accepted_corrections" => ids.size)
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
