require "json"
require "digest"
require "fileutils"
require "time"

scratch = __dir__
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
validation = "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-validation"
completion = JSON.parse(File.read(File.join(validation, "validation-completion-review.json")))
output = File.join(campaign, "validation-failure-review.json")
raise "Failure review already exists" if File.exist?(output)
ids = %w[cholesky_deepseek-v4.1-flash-oc-high_hybrid_r3 roomsim_deepseek-v4.1-flash-oc-high_omp_r2]
raise "Different failures" unless completion.fetch("failures").map { |row| row.fetch("program_id") }.sort == ids.sort
rows = ids.map do |id|
  directory = File.join(validation, "validation", id)
  files = %w[validation_metadata.yaml validation_out_command.log validation_out_stdout.log validation_out_stderr.log validation_out_exitcode.log]
  {
    "program_id" => id, "classification" => "ordinary_generated_program_validation_failure",
    "disposition" => "Retain the unchanged native failure; no repair or retry-until-pass; exclude from timing-review and benchmark candidates.",
    "evidence_sha256" => files.to_h { |name| [name, Digest::SHA256.file(File.join(directory, name)).hexdigest] }
  }
end
source = File.join(scratch, "generated/20261019-134042", ids.first, "cholesky/cholesky.cpp")
text = File.read(source)
raise "Thread override not present" unless text.include?("sysconf(_SC_NPROCESSORS_ONLN)") && text.include?("omp_set_num_threads(preThreads)") && text.include?("configureCpuAffinity(localRank, localSize)")
rows.first.merge!(
  "native_failure" => "libgomp: Thread creation failed: Resource temporarily unavailable",
  "source_sha256" => Digest::SHA256.file(source).hexdigest,
  "source_ranges" => ["478-516", "531-548", "624-627"],
  "static_diagnosis" => "The program replaces launcher affinity with its own online-CPU partition and overrides OMP_NUM_THREADS=8. On the recorded 256-online-CPU host with four local ranks, it requests 64 OpenMP threads per rank, leaving no headroom under the unchanged TasksMax=256 limit for MPI/CUDA support threads. This is consistent with the observed libgomp failure, not evidence of provider or harness unavailability.",
  "host_online_cpus_read_only_check" => 256, "configured_threads_per_rank" => 8,
  "generated_override_threads_per_rank" => 64, "existing_tasks_max" => 256,
  "limits_changed" => false, "diagnostic_program_runs" => 0
)
rows.last["native_failure"] = completion.fetch("failures").find { |row| row.fetch("program_id") == ids.last }.fetch("error")
report = { "reviewed_at" => Time.now.utc.iso8601, "source_commit" => completion.fetch("source_commit"),
  "validation_report_sha256" => Digest::SHA256.file(File.join(validation, "validation-completion-review.json")).hexdigest,
  "scientific_validation_unchanged" => true, "new_eligibility_rule" => false,
  "generation_termination_not_automatic_validation_failure" => true,
  "self_terminated_programs_passing_native_validation" => %w[qtclustering_deepseek-v4.1-flash-oc-high_mpi_r2 qtclustering_deepseek-v4.1-flash-oc-high_hybrid_r4 qtclustering_deepseek-v4.1-flash-oc-high_hybrid_r5],
  "failures" => rows }
File.write(output, JSON.pretty_generate(report) + "\n", mode: "wx")
FileUtils.cp(__FILE__, File.join(campaign, File.basename(__FILE__)))
puts JSON.pretty_generate(report)
