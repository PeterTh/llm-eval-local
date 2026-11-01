# frozen_string_literal: true

require_relative "full_check"

B = UnstructuredBoundaryCheck
F = UnstructuredBoundaryFullCheck
F.check_inputs
completion = B.read_json(File.join(B::EVIDENCE, "completion.json"))
inventory_path = File.join(B::EVIDENCE, "execution-inventory.jsonl")
raise "Execution inventory changed" unless B.sha(inventory_path) == completion.fetch("execution_inventory_sha256")
rows = File.readlines(inventory_path).map { |line| JSON.parse(line) }
original = F.records.to_h { |row| [row.fetch("id"), row] }
raise "Inventory scope changed" unless rows.map { |row| row.fetch("id") }.sort == original.keys.sort
reference, reference_output = F.verify_result(B.read_json(File.join(B::EVIDENCE, "reference.json")))
raise "Reference not successful" unless reference.fetch("passed")
checks = rows.map do |row|
  id = row.fetch("id")
  %w[id backend source_commit source_path origin timing_fixed].each do |key|
    raise "Identity changed: #{id}/#{key}" unless row.fetch(key) == original.fetch(id).fetch(key)
  end
  raise "Completed result changed: #{id}" unless B.sha(F.result_path(id)) == completion.fetch("result_sha256").fetch(id)
  result, output = F.verify_result(row)
  execution = result.fetch("execution")
  internal = output.include?("Validation: PASSED") && !output.include?("Validation: FAILED") && !output.include?("Validation fail")
  comparison = execution.fetch("success") && internal ? validate(reference_output, output, "unstructured") : nil
  passed = execution.fetch("success") && internal && comparison&.first == true
  raise "Recomputed verdict differs: #{id}" unless result.fetch("passed") == passed && result.fetch("comparison") == comparison && result.fetch("internal_validation") == internal
  prefix = File.join(File.dirname(F.result_path(id)), "validation_out")
  exit_code = File.read(prefix + "_exitcode.log").strip
  raise "Exit receipt differs: #{id}" unless exit_code == execution.fetch("exit_code").to_s
  raise "Success with timeout: #{id}" if execution.fetch("success") && execution.fetch("timed_out")
  category = if passed then "pass"
    elsif execution.fetch("timed_out") then "timeout"
    elsif !execution.fetch("success") then "execution_failure"
    elsif !internal then "internal_validation_failure"
    elsif comparison.last.include?("Numeric value mismatch") then "numeric_mismatch"
    else "output_comparison_failure" end
  { "id" => id, "origin" => row.fetch("origin"), "backend" => row.fetch("backend"),
    "source_commit" => row.fetch("source_commit"), "source_path" => row.fetch("source_path"),
    "passed" => passed, "category" => category, "comparison" => comparison,
    "wall_seconds" => execution.fetch("wall_seconds"),
    "result_sha256" => B.sha(F.result_path(id)),
    "log_sha256" => %w[command stdout stderr exitcode wall_time].to_h { |name| [name, B.sha(prefix + "_#{name}.log")] } }
end
raise "Result count differs" unless checks.size == completion.fetch("total")
failed = checks.reject { |row| row.fetch("passed") }
raise "Failed set differs" unless failed.map { |row| row.fetch("id") }.sort == completion.fetch("failed_ids").sort
historical_failed = failed.select { |row| row.fetch("origin") == "published_successful_measurement" }.map { |row| row.fetch("id") }
beam_failed = failed.select { |row| row.fetch("origin") == "beam_validation_pass" }.map { |row| row.fetch("id") }
csv = CSV.read(File.join(B::RELEASE, "release/scored_results.csv"), headers: true)
raise "Published release changed during check" unless B.sha(File.join(B::RELEASE, "release/scored_results.csv")) == B.read_json(File.join(B::EVIDENCE, "manifest.json")).fetch("scored_csv_sha256")
id_for = ->(row) { [row["benchmark"], row["model"], row["par_type"], "r#{row['run']}"].join('_') }
winner_impact = %w[mpi hybrid].to_h do |backend|
  candidates = csv.select { |row| row["benchmark"] == "unstructured" && row["par_type"] == backend && row["benchmark_success"] == "true" }.sort_by { |row| [Float(row["benchmark_median_time"]), id_for.call(row)] }
  remaining = candidates.reject { |row| historical_failed.include?(id_for.call(row)) }
  raise "No remaining successes: #{backend}" if remaining.empty?
  [backend, { "previous" => id_for.call(candidates.first), "after_supplemental_check" => id_for.call(remaining.first),
    "changed" => id_for.call(candidates.first) != id_for.call(remaining.first),
    "previous_median_ms" => Float(candidates.first["benchmark_median_time"]),
    "remaining_median_ms" => Float(remaining.first["benchmark_median_time"]) }]
end
native_passes = LocalEvaluation::ValidationPipeline.new(run_dir: B::BEAM_NATIVE).send(:load_results).values.select(&:output_comparison).map(&:id_string).sort
# The audit schema is recorded verbatim; eligibility is a separate set, never a
# rewrite of the accepted model reviews or their timing verdicts.
audit_paths = %w[20261030-beam10-opencode 20261030-beam10-opencode-qtclustering].map do |name|
  File.join("/home/petert/llm_timing_audit", name, "final/decisions.jsonl")
end
decisions = {}
audit_paths.each do |path|
  File.foreach(path) { |line| row = JSON.parse(line); decisions[row.fetch("program_id")] = row }
end
gate_path = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation/audit-completion-supplemental-review.json"
gate = B.read_json(gate_path)
raise "Timing audit gate failed" unless gate.fetch("passed") && decisions.size == gate.fetch("unique_programs")
timing_invalid = decisions.values.select { |row| row.fetch("final_verdict") == "invalid" }.map { |row| row.fetch("program_id") }.sort
raise "Timing audit invalid count differs" unless timing_invalid.size == gate.fetch("verdicts").fetch("invalid")
raise "Timing correction outside native passes" unless (timing_invalid - native_passes).empty?
report = { "checked_at" => Time.now.utc.iso8601,
  "verified" => true, "total" => checks.size, "passed" => checks.count { |row| row.fetch("passed") }, "failed" => failed.size,
  "categories" => checks.group_by { |row| row.fetch("category") }.transform_values(&:size),
  "by_origin" => checks.group_by { |row| row.fetch("origin") }.transform_values { |rs| { "total" => rs.size, "passed" => rs.count { |r| r.fetch("passed") }, "failed" => rs.count { |r| !r.fetch("passed") } } },
  "runtime_seconds" => checks.sum { |row| row.fetch("wall_seconds") },
  "by_backend_runtime" => checks.group_by { |row| row.fetch("backend") }.transform_values { |rs| { "count" => rs.size, "total_seconds" => rs.sum { |r| r.fetch("wall_seconds") }, "mean_seconds" => rs.sum { |r| r.fetch("wall_seconds") } / rs.size } },
  "failures" => failed, "published_winner_impact" => winner_impact,
  "beam_native_passes" => native_passes.size, "beam_excluded_ids" => beam_failed,
  "beam_eligible_ids" => native_passes - beam_failed,
  "beam_timing_invalid_ids" => timing_invalid,
  "beam_eligible_timing_correction_ids" => timing_invalid - beam_failed,
  "timing_audit_unchanged_sha256" => (audit_paths + [gate_path]).to_h { |path| [path, B.sha(path)] },
  "completion_sha256" => B.sha(File.join(B::EVIDENCE, "completion.json")),
  "checks" => checks, "benchmark_reruns" => 0,
  "integration_policy" => "Supplemental failures are additive validation failures. Preserve original validation and benchmark evidence; exclude failed programs from performance comparisons without altering algorithms or remeasuring unaffected results." }
B.write_json(File.join(B::EVIDENCE, "verification.json"), report)
FileUtils.cp(__FILE__, B::EVIDENCE)
puts JSON.pretty_generate(report.reject { |key, _value| %w[checks beam_eligible_ids beam_timing_invalid_ids beam_eligible_timing_correction_ids failures].include?(key) })
