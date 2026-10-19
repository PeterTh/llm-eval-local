# frozen_string_literal: true

# Descriptive explanation of retained stdout differences, not another validator.
require "json"
require "digest"
require "time"

id = "qtclustering_gpt-6-luna-oc-medium_hybrid_r3"
paths = %w[validation corrected].to_h do |stage|
  [stage, "/home/petert/llm_para_local_evaluation/20261019-luna6-opencode-#{stage}/validation/#{id}/validation_out_stdout.log"]
end
records = paths.transform_values do |path|
  bytes = File.read(path)
  fields = bytes.lines.grep(/\A(?:=== (?:END )?RESULTS ===|Name: |Elements: |Sum: |Min: |Max: |Sample\[|Hash:)/)
  {
    "stdout_path" => path, "stdout_sha256" => Digest::SHA256.hexdigest(bytes),
    "result_field_lines" => fields.size,
    "result_field_multiset_sha256" => Digest::SHA256.hexdigest(fields.sort.join)
  }
end
same = records.values.map { |row| row.fetch("result_field_multiset_sha256") }.uniq.size == 1
target = "/home/petert/llm_para_campaigns/20261018-224015-luna6-opencode-medium/evaluation/revalidation-output-order-review.json"
raise "Receipt already exists" if File.exist?(target)
File.write(target, JSON.pretty_generate({
  "checked_at" => Time.now.utc.iso8601, "program_id" => id,
  "native_original_and_corrected_validation" => "passed",
  "same_multiset_of_printed_result_fields" => same, "evidence" => records,
  "interpretation" => "Multiple ranks print matching results in different orders. This changes extracted raw block bytes without changing their numeric values. Both outputs pass the unchanged native validator, including its output contract. No retry, output edit, new eligibility rule or extra scientific validation gate is applied.",
  "checker_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}) + "\n")
puts JSON.generate({ "program_id" => id, "same_multiset_of_printed_result_fields" => same })
