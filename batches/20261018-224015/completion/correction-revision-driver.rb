# frozen_string_literal: true
$stdout.sync = true
require_relative "experiment/tools/timing_audit/lib/timing_fix_revision"
require_relative "experiment/tools/timing_audit/lib/timing_fix_materializer"
require_relative "experiment/tools/timing_audit/lib/timing_fix_adjudication"
require_relative "reuse-unchanged-correction-reviews"

campaign = "/home/petert/llm_para_campaigns/20261018-224015-luna6-opencode-medium/evaluation"
base = "/home/petert/llm_timing_fixes/20261019-luna6-opencode"
old = { "proposals" => "#{base}-proposals", "review" => "#{base}-review", "adjudication" => "#{base}-review-sol61" }
current = { "proposals" => "#{base}-proposals-revision1", "review" => "#{base}-review-revision1", "adjudication" => "#{base}-review-revision1-sol61" }
id = "cholesky_gpt-6-luna-oc-medium_mpi_r4"
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
  raise "Unexpected unresolved selection" unless progress.fetch("phase") == "awaiting_correction_commit_review" && progress.fetch("unresolved_ids") == [id]
  prior_proposal_path = File.join(old.fetch("proposals"), "proposals", "#{id}.json")
  prior_review_path = File.join(old.fetch("review"), "results", "#{id}.json")
  prior_adjudication_path = File.join(old.fetch("adjudication"), "results", "#{id}.json")
  prior_proposal = JSON.parse(File.read(prior_proposal_path))
  prior_review = JSON.parse(File.read(prior_review_path))
  prior_adjudication = JSON.parse(File.read(prior_adjudication_path))
  raise "Unexpected rejection" unless prior_review.fetch("verdict") == "reject" && prior_adjudication.fetch("final_verdict") == "reject" &&
    prior_adjudication.fetch("confidence") == "high" && prior_adjudication.fetch("timing_only_scope_satisfied")
  fingerprints = old.values.flat_map { |root| Dir[File.join(root, "**", "*")].select { |path| File.file?(path) } }.sort.to_h do |path|
    raise "Symlink in retained evidence" if File.symlink?(path)
    [path, TimingAudit.sha256_file(path)]
  end
  inventory = TimingAudit.load_jsonl(File.join(old.fetch("proposals"), "inventory.jsonl"))
  ids = inventory.map { |row| row.fetch("id") }.sort
  raise "Unexpected correction inventory" unless ids.size == 39 && ids.include?(id)
  unchanged_ids = ids - [id]
  accepted = TimingAudit.load_jsonl(File.join(old.fetch("review"), "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
  raise "Other rejected proposals present" unless unchanged_ids.all? { |key| accepted.fetch(key).fetch("verdict") == "accept" && accepted.fetch(key).fetch("confidence") == "high" }
  feedback_text = "The independent Luna rejection was upheld by Sol 6.1/xhigh. " +
    prior_adjudication.fetch("rationale") + "\nRequired minimal correction: " + prior_adjudication.fetch("minimal_correction") +
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
  TimingFixReviewReuse.run(source: old.fetch("review"), destination: current.fetch("review"), model: "gpt-5.6-luna", effort: "high", only_ids: unchanged_ids)
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
    "prior_adjudication_sha256" => TimingAudit.sha256_file(prior_adjudication_path), "prior_adjudication" => prior_adjudication,
    "feedback" => feedback, "feedback_sha256" => TimingAudit.sha256_file(feedback_path),
    "revised_proposal_sha256" => TimingAudit.sha256_file(File.join(current.fetch("proposals"), "proposals", "#{id}.json")),
    "accepted_review_sha256" => TimingAudit.sha256_file(File.join(current.fetch("review"), "results", "#{id}.json")),
    "prior_evidence_files" => fingerprints.size, "prior_evidence_unchanged" => true,
    "prior_evidence_tree_sha256" => Digest::SHA256.hexdigest(JSON.generate(fingerprints)),
    "unchanged_proposals" => unchanged_ids.size, "reused_independent_reviews" => unchanged_ids.size,
    "new_independent_reviews" => 1, "new_adjudications" => adjudications.size, "accepted_corrections" => ids.size,
    "reuse_receipt_sha256" => TimingAudit.sha256_file(File.join(current.fetch("review"), "reused-reviews.json")),
    "driver_sha256" => TimingAudit.sha256_file(__FILE__),
    "reuse_helper_sha256" => TimingAudit.sha256_file(File.join(__dir__, "reuse-unchanged-correction-reviews.rb")),
    "policy" => "Only the rejected timing proposal is revised and freshly reviewed. The other 38 proposals and literal-prompt-bound accepted reviews are reused unchanged. Every earlier attempt and decision remains intact; no program execution or scientific observation was repeated."
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
