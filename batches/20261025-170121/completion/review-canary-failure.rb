# frozen_string_literal: true

# Recorded evidence and static source only. Never execute or retry a program.
require "json"
require "yaml"
require "digest"
require "open3"
require "time"
require "fileutils"

module BeamCanaryDisposition
  ROOT = "/home/petert/llm_para_local_evaluation/20261030-beam10-opencode-validation"
  CAMPAIGN = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
  REPORT = File.join(CAMPAIGN, "canary-program-failure-review.json")
  FAILED = "black-scholes_beam-1.0-oc-medium_hybrid_r3"
  ORIGINAL = "74652eee82e2473660a7e75f3ad5d77fd0e3759c"
  SOURCE = "20261025-170121/#{FAILED}/black-scholes/black_scholes.cpp"
  module_function

  def evidence
    canaries = File.readlines(File.join(ROOT, "benchmark-campaign/canary-ids.txt"), chomp: true).sort
    expected = %w[cuda_r1 hybrid_r3 mpi_r1 omp_r1].map { |suffix| "black-scholes_beam-1.0-oc-medium_#{suffix}" }.sort
    raise "Canary selection changed" unless canaries == expected
    records = canaries.to_h { |id| [id, YAML.safe_load_file(File.join(ROOT, "benchmark", id, "benchmark_metadata.yaml"))] }
    raise "Unreviewed canary failure" unless records.reject { |_id, row| row.fetch("success") }.keys == [FAILED]
    failed = records.fetch(FAILED)
    execution = failed.fetch("executions").fetch(0)
    unless failed.fetch("args") == ["-n", "100000000"] && failed.fetch("timeout_seconds") == 30 &&
        failed.fetch("executions").size == 1 && execution.fetch("repetition") == "warmup" &&
        execution.fetch("timed_out") && execution.fetch("exit_code") == 124 && !execution.fetch("success")
      raise "Failure is not the reviewed initial warmup timeout"
    end
    directory = File.join(ROOT, "benchmark", FAILED)
    stderr = File.read(File.join(directory, "benchmark_warmup_stderr.log"))
    stdout = File.read(File.join(directory, "benchmark_warmup_stdout.log"))
    command = File.read(File.join(directory, "benchmark_warmup_command.log"))
    unless stderr.include?("expected 1800000000") && stderr.include?("Signal: Segmentation fault (11)") &&
        stderr.include?("MPI_Scatterv") && stderr.include?("Command timed out after 30 seconds.") &&
        stdout.include?("Number of options: 100000000") && !stdout.include?("Pricing options...") &&
        command.include?("command: mpirun --np 4 ")
      raise "Observed failure differs from the reviewed MPI scatter crash"
    end
    source, status = Open3.capture2("git", "-C", File.join(__dir__, "original-backup"), "show", "#{ORIGINAL}:#{SOURCE}")
    raise "Cannot read original source" unless status.success?
    ["std::vector<int> counts(size), displs(size);",
      "displs[r] = static_cast<int>(off * sizeof(OptionInput));",
      "MPI_Scatterv(allOpts.data(), counts.data(), displs.data(), MPI_BYTE,"].each do |line|
      raise "Source no longer matches the reviewed size-limit bug" unless source.include?(line)
    end
    # The observed byte count is 1.8 GB for 25 million options: 72 bytes/option.
    # Rank offsets 3.6 and 5.4 GB exceed signed 32-bit MPI_Scatterv displacements.
    displacements = (0...4).map { |rank| rank * 25_000_000 * 72 }
    paths = canaries.map { |id| File.join(ROOT, "benchmark", id, "benchmark_metadata.yaml") } +
      Dir[File.join(directory, "benchmark_warmup_*.log")].sort +
      [File.join(ROOT, "preflight.yaml"), File.join(ROOT, "benchmark_config.yaml"), __FILE__]
    {
      "schema_version" => 1, "reviewed_failure_ids" => [FAILED], "canary_ids" => canaries,
      "successful_canaries" => 3, "disposition" => "retain ordinary program failure; permit remaining benchmarks",
      "source_commit" => ORIGINAL, "source_path" => SOURCE,
      "source_sha256" => Digest::SHA256.hexdigest(source),
      "diagnosis" => "Program narrows byte displacements to signed 32-bit int before MPI_Scatterv. At the inherited 100-million-option workload, 3.6 GB and 5.4 GB offsets overflow. Retained stderr shows the scatter segmentation fault before pricing starts; the remaining MPI job reaches the unchanged 30-second timeout.",
      "byte_displacements" => displacements, "signed_32_bit_maximum" => 2_147_483_647,
      "infrastructure_assessment" => "Native preflight passed; CUDA, MPI and OpenMP canaries passed. The failed hybrid source independently explains this size-dependent crash; no setup change is warranted.",
      "scope" => "Only this source-pinned ordinary failure is accepted by the canary gate. No source, validation, configuration, resource or measurement changes; no reruns or substitute observations.",
      "retries_requested" => false, "additional_program_executions" => 0,
      "input_sha256" => paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
    }
  end

  def verify!(failures)
    report = JSON.parse(File.read(REPORT))
    raise "Canary disposition changed" unless report.except("reviewed_at") == evidence
    raise "Unreviewed failure in canary gate" unless failures.map { |row| row.fetch("id") }.sort == report.fetch("reviewed_failure_ids")
    raise "Canary failure classification changed" unless failures.all? { |row| row.fetch("classification") == "warmup_timeout" }
    report
  end

  def record!
    raise "Canary disposition already exists" if File.exist?(REPORT)
    report = { "reviewed_at" => Time.now.utc.iso8601 }.merge(evidence)
    File.write(REPORT, JSON.pretty_generate(report) + "\n")
    %w[review-canary-failure.rb verify-benchmark-records-v2.rb launch-measurement-stage-v5.rb].each do |name|
      FileUtils.cp(File.join(__dir__, name), File.join(CAMPAIGN, name))
    end
    puts JSON.pretty_generate(report)
  end
end

if $PROGRAM_NAME == __FILE__
  raise "Use --record" unless ARGV == ["--record"]
  BeamCanaryDisposition.record!
end
