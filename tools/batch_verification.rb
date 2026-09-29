# frozen_string_literal: true
require_relative "artifact_common"

# Checks retained batch evidence without needing the native workspace or Git sources.
module BatchVerification
  def verify_batch(campaign, original, corrected, records)
    base = "batches/#{campaign.fetch('id')}"
    read_json = ->(relative) { JSON.parse(File.read(path("#{base}/#{relative}"))) }
    read_yaml = ->(relative) { LocalEvalArtifact.load_yaml(path("#{base}/#{relative}")) }
    summary = read_json.call("summary.json")
    benchmark_summary = read_json.call("benchmark/summary.json")
    raise "stale batch summary" unless summary.fetch("benchmark") == benchmark_summary
    counts = { "records" => records.size, "successful" => records.values.count { |r| r.fetch("success") },
               "failed" => records.values.count { |r| !r.fetch("success") },
               "timing_fixed" => records.values.count { |r| r.fetch("timing_fixed") },
               "timing_fixed_successful" => records.values.count { |r| r.fetch("timing_fixed") && r.fetch("success") } }
    raise "batch benchmark counts differ" unless counts.all? { |k, v| benchmark_summary.fetch(k) == v }
    raise "batch validation count differs" unless summary.fetch("validation_records") == original.size
    raise "batch validation pass count differs" unless summary.fetch("validation_passed") == records.size
    raise "batch correction count differs" unless summary.fetch("timing_corrections").fetch("benchmark_successful") == counts.fetch("timing_fixed_successful")
    manifest_digest = sha256(path(campaign.fetch("manifest")))
    corrected_manifest_digest = sha256(path("#{base}/timing-corrections/revalidation/provenance/evaluation_manifest.yaml"))
    [[original, campaign.fetch("source_commit"), manifest_digest],
     [corrected, campaign.fetch("corrected_source_commit"), corrected_manifest_digest]].each do |selection, commit, digest|
      selection.each do |id, validation|
        metadata = validation.fetch("metadata")
        raise "batch validation identity differs #{id}" unless metadata.fetch("id") == id && self.class.id(metadata.transform_values(&:to_s)) == id
        raise "batch validation source differs #{id}" unless validation.fetch("source_commit") == commit && validation.fetch("source_batch") == campaign.fetch("id")
        raise "batch validation manifest differs #{id}" unless metadata.fetch("manifest_sha256") == digest
        validation.fetch("logs").each do |name, content|
          raise "batch validation log digest differs #{id}/#{name}" unless Digest::SHA256.hexdigest(content) == validation.fetch("log_sha256").fetch(name)
        end
      end
    end
    corrections = LocalEvalArtifact.read_jsonl(path("#{base}/timing-corrections/final/corrections.jsonl"))
    by_id = corrections.to_h { |r| [r.fetch("program_id"), r] }
    raise "batch correction scope differs" unless by_id.size == corrections.size && by_id.keys.sort == corrected.keys.sort && by_id.keys.sort == records.values.select { |r| r.fetch("timing_fixed") }.map { |r| r.fetch("id") }.sort
    amendment_digest = sha256(path("#{base}/benchmark/provenance/source_correction_amendment.yaml"))
    by_id.each do |id, correction|
      record = records.fetch(id).fetch("timing_correction")
      raise "batch correction amendment differs #{id}" unless record.fetch("source_correction_amendment_sha256") == amendment_digest
      %w[original_source corrected_source].each do |field|
        %w[commit digest].each { |key| raise "batch correction source differs #{id}" unless record.fetch(field).fetch(key) == correction.fetch(field).fetch(key) }
        expected_url = "https://github.com/PeterTh/llm-eval-generated/tree/#{correction.fetch(field).fetch('commit')}/#{campaign.fetch('id')}/#{id}"
        raise "batch correction URL differs #{id}" unless record.fetch(field).fetch("url") == expected_url
      end
      raise "batch correction not accepted #{id}" unless correction.fetch("timing_fixed") && corrected.fetch(id).fetch("metadata").fetch("stages").values.all? { |value| value == true }
      before = original.fetch(id).fetch("logs").fetch("validation_out_stdout.log").scan(/=== RESULTS ===.*?=== END RESULTS ===/m)
      after = corrected.fetch(id).fetch("logs").fetch("validation_out_stdout.log").scan(/=== RESULTS ===.*?=== END RESULTS ===/m)
      raise "batch correction numerical results differ #{id}" unless !before.empty? && before == after
    end
    metadata = read_yaml.call("aggregate/aggregate_metadata.yaml")
    { "manifest_sha256" => "provenance/evaluation_manifest.yaml",
      "benchmark_config_sha256" => "benchmark/provenance/benchmark_config.yaml",
      "source_correction_amendment_sha256" => "benchmark/provenance/source_correction_amendment.yaml",
      "pipeline_amendment_sha256" => "benchmark/provenance/pipeline_amendment.yaml" }.each do |key, relative|
      raise "stale batch aggregate #{key}" unless metadata.fetch(key) == sha256(path("#{base}/#{relative}"))
    end
    receipt = read_json.call("aggregate/export.json")
    raise "batch aggregate CSV differs from native export" unless receipt.fetch("native_aggregate_csv_sha256") == sha256(path(campaign.fetch("aggregate_csv")))
    raise "batch aggregate metadata differs from native export" unless receipt.fetch("native_aggregate_metadata_sha256") == sha256(path("#{base}/aggregate/aggregate_metadata.yaml"))
    raise "batch aggregate incomplete" unless metadata.fetch("complete") && metadata.fetch("record_count") == original.size && receipt.fetch("records") == original.size
    pipeline = read_yaml.call("benchmark/provenance/pipeline_amendment.yaml").fetch("amended_pipeline_source").fetch("files")
    layout = read_json.call("benchmark/method/pipeline-layout.json")
    raise "batch pipeline file set differs" unless layout.keys.sort == pipeline.keys.sort
    layout.each { |name, relative| raise "batch pipeline hash differs #{name}" unless sha256(path("#{base}/#{relative}")) == pipeline.fetch(name) }
  end
end
