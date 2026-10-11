# frozen_string_literal: true

# Resume finalization only: the correction commit already exists. The first
# finalizer stopped before creating evidence because a shared clone's origin
# was a local path rather than the canonical GitHub URL. No program was rerun.
require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/tools/timing_audit/lib/timing_fix_finalize"

campaign = "/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh/evaluation"
source = "/tmp/sol61-evaluation-20261010.xL0RJx/corrected"
original = "6adaf64dc195651e5b3da3575738874e09fdc72d"
corrected = "8bfe74f8bfb8397f57f524c7e8b5981a985253f7"
proposals = "/home/petert/llm_timing_fixes/20261010-sol61-proposals"
output = "/home/petert/llm_timing_fixes/20261010-sol61-final"
raise "Wrong correction parent" unless TimingAudit.capture!("git", "-C", source, "rev-parse", "HEAD^").strip == original
raise "Wrong canonical repository" unless TimingFixFinalize.repository_https_url(source) == "https://github.com/PeterTh/llm-eval-generated"
compiled = TimingFixFinalize.load_yaml(File.join(proposals, "materialized/summary-full.yaml"))
raise "Incomplete compilation" unless compiled.fetch("compile_successes") == 11 && compiled.fetch("compile_failures").empty?
raise "Compiled patch changed" unless compiled.fetch("patch_sha256") == TimingAudit.sha256_file(File.join(proposals, "materialized/timing-fixes-full.patch"))
manifest = TimingFixFinalize.run(proposal_root: proposals,
  review_root: "/home/petert/llm_timing_fixes/20261010-sol61-review",
  adjudication_root: "/home/petert/llm_timing_fixes/20261010-sol61-review-sol61",
  source_root: source, corrected_commit: corrected, output_dir: output)
raise "Wrong correction count" unless manifest.fetch("record_count") == 11
paths = TimingAudit.capture!("git", "-C", source, "diff", "--name-only", original, corrected, "--").lines(chomp: true).sort
report = {
  "created_at" => TimingAudit.utc_now, "original_commit" => original,
  "corrected_commit" => corrected, "corrections" => 11, "changed_paths" => paths,
  "materialized_patch_sha256" => compiled.fetch("patch_sha256"),
  "registry_manifest_sha256" => TimingAudit.sha256_file(File.join(output, "manifest.yaml")),
  "source_root" => source, "pushed" => false, "revalidation_started" => false,
  "operational_note" => "Finalization resumed after setting the isolated shared clone's origin to the canonical GitHub URL; the existing correction commit was retained unchanged."
}
path = File.join(campaign, "correction-commit.json")
raise "Correction receipt already exists" if File.exist?(path)
TimingAudit.atomic_write(path, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
