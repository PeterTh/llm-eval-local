# frozen_string_literal: true
require "json"
require "digest"
require "time"
require "fileutils"
require "open3"
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
id = "unstructured_beam-1.0-oc-medium_mpi_r2"
source_commit = "74652eee82e2473660a7e75f3ad5d77fd0e3759c"
source_relative = "20261025-170121/#{id}/unstructured/unstructured.cpp"
source_path = File.join(__dir__, "generated", source_relative)
bytes, status = Open3.capture2("git", "-C", File.join(__dir__, "generated"), "show", "#{source_commit}:#{source_relative}")
raise "Original source mismatch" unless status.success? && bytes == File.binread(source_path)
validation = "/home/petert/llm_para_local_evaluation/20261030-beam10-opencode-validation"
native_path = File.join(validation, "validation", id)
review_path = "/home/petert/llm_timing_audit/20261030-beam10-opencode-supplemental-communication-20261031/results/#{id}.json"
review = JSON.parse(File.read(review_path))
raise "Independent finding missing" unless review.fetch("notes").include?("interleaved halo-transfer defect") && review.fetch("confidence") == "high"
command_path = File.join(native_path, "validation_out_command.log")
raise "Validation configuration differs" unless File.read(command_path).include?("-v -r -n 256 -i 20") && File.read(command_path).include?("mpirun --np 4")
baseline = "/home/petert/llm_para_local_evaluation/20260819-003427/benchmark_config.yaml"
raise "Inherited benchmark changed" unless Digest::SHA256.file(baseline).hexdigest == "20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970"
paths = [source_path, review_path, baseline, command_path,
  File.join(native_path, "validation_metadata.yaml"), File.join(native_path, "validation_out_stdout.log"),
  File.join(validation, "validation/all_validation_results.yaml")]
report = {
  "recorded_at" => Time.now.utc.iso8601, "status" => "awaiting_user_direction",
  "program_id" => id, "classification" => "pre_existing_algorithmic_halo_transfer_defect_missed_by_small_validation",
  "source_commit" => source_commit, "source_path" => source_relative,
  "source_url" => "https://github.com/PeterTh/llm-eval-generated/blob/#{source_commit}/#{source_relative}",
  "source_findings" => [
    { "lines" => "32-35", "finding" => "Each ElementDynamic contains two doubles: current_energy and total_flux." },
    { "lines" => "183-192", "finding" => "Sending n contiguous MPI_DOUBLE values from a current_energy address transfers both fields of n/2 elements, not the n current_energy values. The second half of every ghost row remains unupdated." },
    { "lines" => "107-155", "finding" => "Initial dynamic values are zero; the only nonzero external-flow materials are the four global corners. Connectivity is nearest-neighbor." },
    { "lines" => "180-212", "finding" => "Each iteration reads the previous state and writes the next state; influence can advance by at most one grid edge per iteration." }
  ],
  "why_native_validation_misses_it" => {
    "n" => 256, "iterations" => 20, "mpi_ranks" => 4, "owned_rows_per_rank" => 64,
    "reasoning" => "Twenty nearest-neighbor updates cannot carry corner-generated values to the first inter-rank boundary, 63 edges from either global x edge. All exchanged halo energies remain zero in this validation case, so omitted halo entries are indistinguishable from correct transfers."
  },
  "full_benchmark_exposure" => {
    "n" => 2000, "iterations" => 5000, "mpi_ranks" => 128,
    "owned_rows" => [15, 16],
    "reasoning" => "The corner-generated field reaches rank boundaries within the benchmark iteration count. The omitted latter-half halo energies are required by the computation. This is not a timing defect or a Hash-only discrepancy."
  },
  "independent_confirmation" => { "model" => "gpt-6.1-sol", "effort" => "xhigh", "source_only" => true, "result" => review_path },
  "native_validation_result" => "passed; preserved unchanged as raw evidence",
  "generated_program_executions_for_this_investigation" => 0,
  "algorithmic_edits" => 0, "corrections_launched" => false, "benchmarking_launched" => false,
  "recommendation" => "Preserve the original code and recorded validation pass; count this known algorithmically incorrect implementation as failing in the adjudicated dataset, not repair its algorithm. Add a boundary-crossing validation case for Unstructured MPI/hybrid and apply it consistently to existing passing implementations; retain all earlier evidence and change only affected results. Request user direction before changing scientific validation scope or release eligibility.",
  "input_sha256" => paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
  "recorder_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
output = File.join(campaign, "scientific-followup-hold.json")
raise "Concern already retained" if File.exist?(output)
File.write(output, JSON.pretty_generate(report) + "\n", mode: "wx")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.reject { |key, _| key == "input_sha256" })
