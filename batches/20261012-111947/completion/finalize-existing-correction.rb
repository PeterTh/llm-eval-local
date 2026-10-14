# frozen_string_literal: true

# Only finalize evidence for the existing commit. The first attempt stopped
# because the isolated shared clone's origin was a local path, not GitHub.
require "/tmp/haiku55-evaluation-20261014.ZqhO2v/experiment/tools/timing_audit/lib/timing_fix_finalize"

campaign = "/home/petert/llm_para_campaigns/20261012-111947-haiku55-medium/evaluation"
source = "/tmp/haiku55-evaluation-20261014.ZqhO2v/corrected"
original = "71ba7cc523997c8fd1537d7a8159b583f260793d"
corrected = "778f868b8e30433e60115c46bf01dbf84c609765"
proposals = "/home/petert/llm_timing_fixes/20261014-haiku55-proposals"
output = "/home/petert/llm_timing_fixes/20261014-haiku55-final"
raise "Wrong correction commit" unless TimingAudit.capture!("git", "-C", source, "rev-parse", "HEAD").strip == corrected
raise "Wrong correction parent" unless TimingAudit.capture!("git", "-C", source, "rev-parse", "HEAD^").strip == original
raise "Wrong canonical repository" unless TimingFixFinalize.repository_https_url(source) == "https://github.com/PeterTh/llm-eval-generated"
compiled = TimingFixFinalize.load_yaml(File.join(proposals, "materialized/summary-full.yaml"))
raise "Incomplete compilation" unless compiled.fetch("compile_successes") == 33 && compiled.fetch("compile_failures").empty?
raise "Compiled patch changed" unless compiled.fetch("patch_sha256") == TimingAudit.sha256_file(File.join(proposals, "materialized/timing-fixes-full.patch"))
manifest = TimingFixFinalize.run(proposal_root: proposals,
  review_root: "/home/petert/llm_timing_fixes/20261014-haiku55-review",
  adjudication_root: "/home/petert/llm_timing_fixes/20261014-haiku55-review-sol61",
  source_root: source, corrected_commit: corrected, output_dir: output)
raise "Wrong correction count" unless manifest.fetch("record_count") == 33
paths = TimingAudit.capture!("git", "-C", source, "diff", "--name-only", original, corrected, "--").lines(chomp: true).sort
report = {
  "created_at" => TimingAudit.utc_now, "original_commit" => original,
  "corrected_commit" => corrected, "corrections" => 33, "changed_paths" => paths,
  "materialized_patch_sha256" => compiled.fetch("patch_sha256"),
  "registry_manifest_sha256" => TimingAudit.sha256_file(File.join(output, "manifest.yaml")),
  "source_root" => source, "pushed" => false, "revalidation_started" => false,
  "operational_note" => "Finalization resumed after setting the isolated shared clone's origin to the canonical GitHub URL. The original single correction commit was retained unchanged; no patch was regenerated and no program was rerun."
}
path = File.join(campaign, "correction-commit.json")
raise "Correction receipt already exists" if File.exist?(path)
TimingAudit.atomic_write(path, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.slice("original_commit", "corrected_commit", "corrections", "source_root", "pushed"))
