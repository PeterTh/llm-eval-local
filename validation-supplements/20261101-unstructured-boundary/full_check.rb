# frozen_string_literal: true

require_relative "boundary_check"
require "thread"

module UnstructuredBoundaryFullCheck
  extend self
  B = UnstructuredBoundaryCheck
  BUILD_WORKERS = 4

  def records
    File.readlines(File.join(B::EVIDENCE, "inventory.jsonl")).map { |line| JSON.parse(line) }
  end

  def result_path(id)
    File.join(B::EVIDENCE, "results", id, "result.json")
  end

  def verify_result(row)
    result = B.read_json(result_path(row.fetch("id")))
    %w[id backend source_commit source_path].each do |key|
      raise "Result identity changed: #{key}" unless result.fetch(key) == row.fetch(key)
    end
    raise "Result arguments differ" unless result.fetch("arguments") == B::ARGS
    raise "Result executable differs" unless result.fetch("executable_sha256") == row.fetch("cache").fetch("executable_sha256")
    output = File.read(File.join(File.dirname(result_path(row.fetch("id"))), "validation_out_stdout.log"))
    raise "Result output changed" unless Digest::SHA256.hexdigest(output) == result.fetch("output_sha256")
    [result, output]
  end

  def prepare
    B.check_inputs
    raise "Full launch already prepared" if File.exist?(File.join(B::EVIDENCE, "full-manifest.json"))
    pilot = B.read_json(File.join(B::EVIDENCE, "pilot.json"))
    raise "Pilot gate failed" unless pilot.fetch("passed")
    reference = B.read_json(File.join(B::EVIDENCE, "reference.json"))
    reused = [reference] + records.select { |row| ([B::KNOWN_BAD] + B::CONTROLS).include?(row.fetch("id")) }
    reused.each { |row| verify_result(row) }
    FileUtils.cp(__FILE__, B::EVIDENCE)
    B.write_json(File.join(B::EVIDENCE, "full-manifest.json"), {
      "created_at" => Time.now.utc.iso8601,
      "parent_manifest_sha256" => B.sha(File.join(B::EVIDENCE, "manifest.json")),
      "pilot_sha256" => B.sha(File.join(B::EVIDENCE, "pilot.json")),
      "driver_sha256" => B.sha(__FILE__), "build_workers" => BUILD_WORKERS,
      "reused_result_sha256" => reused.to_h { |row| [row.fetch("id"), B.sha(result_path(row.fetch("id")))] },
      "policy" => "Rebuild only missing exact-source caches with the unchanged native build procedure; four compile workers, then serial four-rank validation. Reuse all completed pilot cases; no model requests or benchmark reruns."
    })
    puts JSON.pretty_generate(B.read_json(File.join(B::EVIDENCE, "full-manifest.json")))
  end

  def check_inputs
    B.check_inputs
    full = B.read_json(File.join(B::EVIDENCE, "full-manifest.json"))
    raise "Full driver changed" unless B.sha(__FILE__) == full.fetch("driver_sha256")
    raise "Parent manifest changed" unless B.sha(File.join(B::EVIDENCE, "manifest.json")) == full.fetch("parent_manifest_sha256")
    raise "Pilot changed" unless B.sha(File.join(B::EVIDENCE, "pilot.json")) == full.fetch("pilot_sha256")
    full.fetch("reused_result_sha256").each do |id, digest|
      raise "Pilot result changed: #{id}" unless B.sha(result_path(id)) == digest
    end
    full
  end

  def rebuild(row)
    id = row.fetch("id")
    receipt_path = File.join(B::EVIDENCE, "builds", id, "build-binding.json")
    if File.file?(receipt_path)
      binding = B.read_json(receipt_path)
      raise "Previously failed build requires investigation: #{id}" unless binding.fetch("success")
      return binding.fetch("row")
    end
    local = File.join(B::SCRATCH, "rebuilds", id)
    raise "Partial rebuild requires inspection: #{local}" if File.exist?(local)
    expected = row.fetch("staged_source_git_blob_ids")
    raise "Pinned source map changed" unless B.source_files(B::SOURCE, row.fetch("source_commit"), row.fetch("source_path")) == expected
    materialized = File.join(local, "git-source")
    expected.each do |relative, oid|
      raise "Unsafe source path" if relative.start_with?('/') || relative.split('/').include?('..')
      bytes = B.capture("git", "-C", B::SOURCE, "cat-file", "blob", oid)
      raise "Git blob differs" unless Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0" + bytes) == oid
      LocalEvaluation.atomic_write(File.join(materialized, relative), bytes)
    end
    staged = LocalEvaluation::BuildSupport.stage_source(source_root: materialized, benchmark: "unstructured", stage_root: File.join(local, "source"))
    evidence = File.dirname(receipt_path)
    FileUtils.mkdir_p(evidence)
    FileUtils.cp(File.join(local, "source_staging.yaml"), evidence)
    built, error = LocalEvaluation::BuildSupport.build(source_dir: staged, build_dir: File.join(local, "build"),
      runner: LocalEvaluation::ProcessRunner.new, par_type: row.fetch("backend"), log_dir: evidence)
    unless built
      B.write_json(receipt_path, { "id" => id, "success" => false, "error" => error, "source_commit" => row.fetch("source_commit") })
      raise "Rebuild failed; inspect preserved logs: #{id}: #{error}"
    end
    binary = LocalEvaluation::BuildSupport.find_executable(File.join(local, "build"), "unstructured")
    files = %w[source_staging.yaml cmake_command.log cmake_exitcode.log build_command.log build_exitcode.log build_wall_time.log]
    bound = row.merge("cache" => {
      "directory" => evidence, "executable" => binary, "executable_sha256" => B.sha(binary),
      "staged_source_git_blob_ids" => expected,
      "build_evidence_sha256" => files.to_h { |name| [name, B.sha(File.join(evidence, name))] },
      "reuse_basis" => "New local-only build from exact pinned Git blob bytes using the unchanged native compiler and CMake procedure."
    })
    B.write_json(receipt_path, { "id" => id, "success" => true, "built_at" => Time.now.utc.iso8601, "row" => bound })
    puts JSON.generate("stage" => "build", "id" => id, "success" => true)
    bound
  end

  def progress(data)
    LocalEvaluation.atomic_write(File.join(B::EVIDENCE, "progress.json"), JSON.pretty_generate(data.merge("updated_at" => Time.now.utc.iso8601)) + "\n")
  end

  def run
    $stdout.sync = true
    check_inputs
    raise "Full check already complete" if File.exist?(File.join(B::EVIDENCE, "completion.json"))
    pids, _err, status = Open3.capture3("pgrep", "-u", "llmtest")
    raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
    lock = LocalEvaluation::HostPerformanceLock.new
    resources = LocalEvaluation::Resources.new
    topology = resources.verify_topology!
    LocalEvaluation.ensure_disk_space!(B::SCRATCH)
    unless File.exist?(File.join(B::EVIDENCE, "host.json"))
      B.write_json(File.join(B::EVIDENCE, "host.json"), { "checked_at" => Time.now.utc.iso8601, "environment" => LocalEvaluation.environment_snapshot, "topology" => topology })
    end
    rows = records
    pending = rows.reject { |row| row["cache"] }
    progress("stage" => "build", "needed" => pending.size, "completed" => 0)
    queue = Queue.new
    pending.each { |row| queue << row }
    bindings = {}
    failures = []
    mutex = Mutex.new
    workers = Array.new(BUILD_WORKERS) do
      Thread.new do
        loop do
          row = begin
            queue.pop(true)
          rescue ThreadError
            break
          end
          begin
            binding = rebuild(row)
            mutex.synchronize do
              bindings[row.fetch("id")] = binding
              progress("stage" => "build", "needed" => pending.size, "completed" => bindings.size, "errors" => failures)
            end
          rescue StandardError => e
            mutex.synchronize { failures << { "id" => row.fetch("id"), "error" => "#{e.class}: #{e.message}" } }
          end
        end
      end
    end
    workers.each(&:join)
    raise "Build stage needs inspection: #{failures.to_json}" unless failures.empty?
    rows = rows.map { |row| row["cache"] ? row : bindings.fetch(row.fetch("id")) }
    execution_inventory = File.join(B::EVIDENCE, "execution-inventory.jsonl")
    bytes = rows.map { |row| JSON.generate(row) + "\n" }.join
    if File.exist?(execution_inventory)
      raise "Execution inventory changed" unless File.read(execution_inventory) == bytes
    else
      LocalEvaluation.atomic_write(execution_inventory, bytes)
    end
    reference, output = verify_result(B.read_json(File.join(B::EVIDENCE, "reference.json")))
    raise "Reference failed" unless reference.fetch("passed")
    runner = LocalEvaluation::ProcessRunner.new
    results = []
    started = Time.now.utc
    rows.each do |row|
      result = if File.exist?(result_path(row.fetch("id")))
        verify_result(row).first
      else
        B.execute(row, resources: resources, runner: runner, reference_output: output).first
      end
      results << result
      elapsed = Time.now.utc - started
      progress("stage" => "validation", "completed" => results.size, "total" => rows.size,
        "passed" => results.count { |r| r.fetch("passed") }, "failed" => results.count { |r| !r.fetch("passed") },
        "last_id" => row.fetch("id"), "elapsed_seconds" => elapsed,
        "estimated_remaining_seconds" => elapsed / results.size * (rows.size - results.size))
    end
    origins = rows.to_h { |row| [row.fetch("id"), row.fetch("origin")] }
    summary = { "completed_at" => Time.now.utc.iso8601, "total" => rows.size,
      "passed" => results.count { |r| r.fetch("passed") }, "failed" => results.count { |r| !r.fetch("passed") },
      "by_origin" => results.group_by { |r| origins.fetch(r.fetch("id")) }.transform_values { |rs| { "total" => rs.size, "passed" => rs.count { |r| r.fetch("passed") }, "failed" => rs.count { |r| !r.fetch("passed") } } },
      "failed_ids" => results.reject { |r| r.fetch("passed") }.map { |r| r.fetch("id") },
      "result_sha256" => results.to_h { |r| [r.fetch("id"), B.sha(result_path(r.fetch("id")))] },
      "execution_inventory_sha256" => B.sha(execution_inventory),
      "manifest_sha256" => B.sha(File.join(B::EVIDENCE, "manifest.json")),
      "full_manifest_sha256" => B.sha(File.join(B::EVIDENCE, "full-manifest.json")),
      "benchmark_runs" => 0, "model_requests" => 0, "algorithmic_edits" => 0,
      "policy" => "Results are supplemental evidence pending additive release/eligibility integration; original evidence and measurements remain unchanged." }
    B.write_json(File.join(B::EVIDENCE, "completion.json"), summary)
    progress(summary.reject { |k, _v| k == "result_sha256" }.merge("stage" => "complete"))
    puts JSON.pretty_generate(summary.reject { |k, _v| k == "result_sha256" })
  rescue StandardError => e
    progress("stage" => "needs_inspection", "error" => "#{e.class}: #{e.message}")
    raise
  ensure
    lock&.close
  end
end

if $PROGRAM_NAME == __FILE__
  raise "Use prepare or run" unless ARGV.size == 1 && %w[prepare run].include?(ARGV.first)
  UnstructuredBoundaryFullCheck.public_send(ARGV.first)
end
