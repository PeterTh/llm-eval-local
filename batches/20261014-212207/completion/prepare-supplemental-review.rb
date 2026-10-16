# frozen_string_literal: true

require_relative "experiment/tools/timing_audit/lib/timing_audit"

campaign = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
prior = "/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh/evaluation/mpi-split-evidence"
artifact = File.join(__dir__, "release")
published_prefix = "batches/20261006-204623/timing-audit/mpi-split-evidence"
target = File.join(campaign, "mpi-split-evidence")
id = "qtclustering_claude-sonnet-5.5-cc-medium_hybrid_r1"
native = File.join("/home/petert/llm_para_local_evaluation/20261015-sonnet55-validation/validation", id)
library = "/usr/lib/x86_64-linux-gnu/libmpi.so.40.30.6"
raise "Supplemental evidence already exists" if File.exist?(target)
old = JSON.parse(File.read(File.join(prior, "evidence.json")))
old.fetch("files_sha256").each do |name, sha|
  raise "Prior platform evidence changed: #{name}" unless TimingAudit.sha256_file(File.join(prior, name)) == sha
end
raise "MPI library differs from the retained static proof" unless TimingAudit.sha256_file(library) == old.fetch("library_sha256") &&
  File.realpath("/usr/lib/x86_64-linux-gnu/openmpi/lib/libmpi.so") == library
command = File.join(native, "validation_out_command.log")
raise "Unexpected MPI loader override" if File.read(command).match?(/\bLD_(?:PRELOAD|LIBRARY_PATH)=/)
source = File.read(File.join(prior, "openmpi-v4.1.6-comm.c")).lines
raise "MPI source excerpt shifted" unless source[797].start_with?("int ompi_comm_split_type") && source[821].include?("coll_allreduce (MPI_IN_PLACE, &tmp, 4, MPI_INT, MPI_MAX")
commands = {
  "program-dynamic-section" => ["readelf", "-d", File.join(native, "qtclustering")],
  "packages" => ["dpkg-query", "-W", "libopenmpi3t64", "libopenmpi-dev", "openmpi-bin"]
}
records = commands.to_h do |name, argv|
  stdout, stderr, status = Open3.capture3(*argv)
  raise "Static inspection failed: #{name}: #{stderr}" unless status.success?
  if name == "program-dynamic-section"
    raise "MPI link binding differs" unless stdout.include?("Shared library: [libmpi.so.40]") &&
      stdout.include?("Library runpath: [/usr/lib/x86_64-linux-gnu/openmpi/lib]")
  else
    raise "MPI packages changed" unless TimingAudit.sha256_bytes(stdout) == old.dig("commands", "packages", "stdout_sha256")
  end
  TimingAudit.atomic_write(File.join(target, "#{name}.stdout.txt"), stdout)
  TimingAudit.atomic_write(File.join(target, "#{name}.stderr.txt"), stderr)
  [name, { "argv" => argv, "exit_code" => status.exitstatus,
    "stdout_sha256" => TimingAudit.sha256_bytes(stdout), "stderr_sha256" => TimingAudit.sha256_bytes(stderr) }]
end
reused = old.fetch("files_sha256").reject { |name, _| name.start_with?("program-dynamic-section", "packages") || name == "retain-evidence.rb" }
reused["evidence.json"] = TimingAudit.sha256_file(File.join(prior, "evidence.json"))
reused["supplemental-context.txt"] = TimingAudit.sha256_file(File.join(prior, "supplemental-context.txt"))
layout = reused.to_h do |name, sha|
  stored = name.end_with?(".c") ? "#{name}.txt" : name
  relative = File.join(published_prefix, stored)
  raise "Published MPI evidence differs: #{relative}" unless TimingAudit.sha256_file(File.join(artifact, relative)) == sha
  [name, { "path" => relative, "sha256" => sha }]
end
context = File.read(File.join(prior, "supplemental-context.txt"))
  .sub("starts at line 738", "starts at line 798")
  .sub("lines 754-764", "lines 816-823")
context += "\nCurrent campaign binding: the Sonnet QT hybrid r1 validation executable has the\n"
context += "same MPI NEEDED/RUNPATH binding and no recorded loader overrides. The MPI library\n"
context += "SHA-256 and package versions match the retained proof exactly. No generated\n"
context += "program or probe was run again. Source line numbers above refer to the retained\n"
context += "upstream file; the earlier context's line-number typo is corrected here.\n\n"
context += "Retained implementation excerpt (openmpi-v4.1.6-comm.c):\n"
context += source[797..828].each_with_index.map { |line, index| "#{798 + index}: #{line}" }.join
TimingAudit.atomic_write(File.join(target, "supplemental-context.txt"), context)
TimingAudit.atomic_write(File.join(target, "reuse-layout.json"), JSON.pretty_generate(layout) + "\n")
report = {
  "created_at" => TimingAudit.utc_now, "program_id" => id,
  "library" => library, "library_sha256" => TimingAudit.sha256_file(library),
  "generated_binary_sha256" => TimingAudit.sha256_file(File.join(native, "qtclustering")),
  "validation_command_sha256" => TimingAudit.sha256_file(command),
  "commands" => records, "reused_artifacts" => layout,
  "context_sha256" => TimingAudit.sha256_bytes(context),
  "generated_program_runs" => 0, "new_compilations" => 0,
  "driver_sha256" => TimingAudit.sha256_file(__FILE__),
  "policy" => "Reuse the exact pinned library's retained source, disassembly and compile-only layout proof; inspect only the new executable's dynamic section. No prior program verdict supplied to the reviewer."
}
TimingAudit.atomic_write(File.join(target, "evidence.json"), JSON.pretty_generate(report) + "\n")
selection = [{ "program_id" => id,
  "reason" => "The general Sol review is medium-confidence valid based on the pinned MPI_Comm_split_type implementation; the independent QT Luna review is high-confidence invalid for rank-local timing. Resolve this genuine disagreement with the retained library-specific static evidence and the complete QT preprocessing contract." }]
TimingAudit.atomic_write(File.join(campaign, "mpi-split-selection.jsonl"), TimingAudit.dump_jsonl(selection))
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.slice("program_id", "library_sha256", "generated_program_runs", "new_compilations"))
