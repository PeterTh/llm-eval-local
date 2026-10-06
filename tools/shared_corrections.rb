# frozen_string_literal: true
require_relative "artifact_common"

# A single accepted timing-only source commit can cover multiple campaigns.
# Historical records stay immutable; this object verifies and applies only the
# explicit revalidation and remeasurement scope to the current release view.
class SharedCorrections
  include LocalEvalArtifact
  attr_reader :validations, :benchmarks, :registry, :histories, :base, :historical_config, :historical_config_digest

  def initialize(root, config)
    @root, @config = root, config
    @base = config.fetch("root")
    @registry = read_jsonl(file("final/corrections.jsonl")).to_h { |r| [r.fetch("program_id"), r] }
    @validations = read_partitions("revalidation/validation/records")
    @benchmarks = read_partitions("benchmark/records")
    @histories = read_jsonl(file("source-history.jsonl")).to_h { |r| [r.fetch("id"), r] }
    @historical_config = load_yaml(file("benchmark/provenance/benchmark_config.yaml"))
    @historical_config_digest = sha256(file("benchmark/provenance/benchmark_config.yaml"))
  end

  def file(relative)
    joined = File.expand_path(File.join(@base, relative), @root)
    raise "unsafe correction path" unless joined.start_with?(File.expand_path(@root) + "/")
    joined
  end

  def read_partitions(relative)
    records = Dir[File.join(file(relative), "*/*.jsonl")].sort.flat_map { |p| read_jsonl(p) }
    index = records.to_h { |r| [r.fetch("id"), r] }
    raise "duplicate correction IDs #{relative}" unless index.size == records.size
    index
  end

  def stages(record)
    record["stages"] || record.fetch("metadata").fetch("stages")
  end

  def passed?(record)
    VALIDATION_STAGES.all? { |s| stages(record).fetch(s) == true }
  end

  def stdout(record)
    record["logs"] ? record.fetch("logs").fetch("validation_out_stdout.log") : record.fetch("execution").fetch("stdout")
  end

  def records_digest(records)
    Digest::SHA256.hexdigest(canonical_json_for_digest(records.sort.to_h))
  end

  def verify!(catalog, loader)
    original_validations, old_benchmarks, all_benchmarks = {}, {}, {}
    catalog.fetch("campaigns").each do |campaign|
      selection = loader.call(campaign.fetch("validation_records"))
      if campaign["corrected_validation_records"]
        selection.merge!(loader.call(campaign.fetch("corrected_validation_records")))
      end
      raise "overlapping validation IDs" unless (original_validations.keys & selection.keys).empty?
      original_validations.merge!(selection)
      records = loader.call(campaign.fetch("benchmark_records"))
      in_historical_scope = if @config["baseline_campaign_ids"]
        @config.fetch("baseline_campaign_ids").include?(campaign.fetch("id"))
      else
        campaign.fetch("validation_format") != "shared"
      end
      old_benchmarks.merge!(records) if in_historical_scope
      all_benchmarks.merge!(records)
    end
    expected = @config.fetch("expected")
    raise "shared correction scope differs" unless @registry.size == expected.fetch("corrections") &&
      @registry.keys.sort == @validations.keys.sort && @registry.keys.sort == @histories.keys.sort &&
      (@registry.keys - original_validations.keys).empty?
    raise "historical replacement scope differs" unless @benchmarks.size == expected.fetch("historical_benchmarks") &&
      @benchmarks.keys.sort == (@registry.keys & old_benchmarks.keys).sort && @benchmarks.keys.all? { |id| id.start_with?("qtclustering_") }
    guard = JSON.parse(File.read(file("release-guard.json")))
    raise "historical replacement IDs changed" unless guard.fetch("affected_ids") == @benchmarks.keys.sort
    unaffected = old_benchmarks.reject { |id, _| @benchmarks.key?(id) }
    raise "unrelated historical records changed" unless unaffected.size == guard.fetch("unaffected_records") && records_digest(unaffected) == guard.fetch("unaffected_records_sha256")
    raise "historical baseline changed" unless records_digest(old_benchmarks) == guard.fetch("prior_records_sha256")
    guard.fetch("immutable_input_files").each do |relative, digest|
      raise "archived input changed #{relative}" unless sha256(File.join(@root, relative)) == digest
    end
    final = load_yaml(file("final/manifest.yaml"))
    raise "shared correction registry digest differs" unless final.fetch("record_count") == @registry.size && final.dig("artifacts", "corrections_jsonl_sha256") == sha256(file("final/corrections.jsonl"))
    manifest_digest = sha256(file("revalidation/provenance/evaluation_manifest.yaml"))
    failure_data = JSON.parse(File.read(file("final/validation-failures.json")))
    failures = failure_data.fetch("records").to_h { |r| [r.fetch("program_id"), r] }
    failed = @validations.reject { |_, r| passed?(r) }
    raise "unresolved corrected validation failure" unless failures.keys.sort == failed.keys.sort && failed.size == expected.fetch("failed_revalidations") && failure_data.fetch("corrected_validation_manifest_sha256") == manifest_digest
    proposals = read_jsonl(file("proposals/results.jsonl")).to_h { |r| [r.fetch("program_id"), r] }
    reviews = read_jsonl(file("postfix-review/results.jsonl")).to_h { |r| [r.fetch("program_id"), r] }
    raise "proposal/review scope differs" unless [proposals.keys.sort, reviews.keys.sort].all? { |ids| ids == @registry.keys.sort }
    @registry.each do |id, correction|
      validation = @validations.fetch(id)
      previous_validation = original_validations.fetch(id)
      raise "correction was not accepted #{id}" unless correction.fetch("timing_fixed") && correction.fetch("final_verdict") == "accept" && passed?(previous_validation)
      raise "shared validation provenance differs #{id}" unless validation.fetch("source_batch") == correction.fetch("source_batch") &&
        validation.fetch("source_commit") == correction.dig("corrected_source", "commit") && validation.dig("metadata", "manifest_sha256") == manifest_digest
      verify_validation_logs!(validation)
      %w[original corrected].each do |kind|
        source = correction.fetch("#{kind}_source")
        raise "shared correction revision differs #{id}" unless source.fetch("commit") == final.dig("#{kind}_source", "commit")
        url = "https://github.com/PeterTh/llm-eval-generated/tree/#{source.fetch('commit')}/#{correction.fetch('source_prefix')}"
        raise "shared correction source URL differs #{id}" unless correction.fetch("#{kind}_source_url") == url
      end
      { "proposal" => proposals.fetch(id), "postfix_review" => reviews.fetch(id) }.each do |kind, result|
        digest = Digest::SHA256.hexdigest(JSON.pretty_generate(result) + "\n")
        raise "shared #{kind} evidence differs #{id}" unless correction.fetch(kind).fetch("sha256") == digest
      end
      raise "independent correction review rejected #{id}" unless reviews.fetch(id).fetch("verdict") == "accept"
      if failed.key?(id)
        decision = failures.fetch(id)
        raise "invalid failed-validation disposition #{id}" unless decision.fetch("decision") == "fail_validation" &&
          decision.dig("authorization", "source") == "user" && !decision.dig("authorization", "statement").to_s.empty? &&
          decision.fetch("failed_stage") == VALIDATION_STAGES.find { |s| stages(validation).fetch(s) != true } &&
          decision.dig("validation_evidence", "metadata_sha256") == validation.fetch("metadata_sha256") &&
          decision.dig("validation_evidence", "stdout_sha256") == Digest::SHA256.hexdigest(stdout(validation)) &&
          decision.dig("original_validation", "stdout_sha256") == Digest::SHA256.hexdigest(stdout(previous_validation))
        raise "excluded validation has a benchmark #{id}" if all_benchmarks.key?(id) || @benchmarks.key?(id)
        review = file("final/unexpected-validation/#{id}/sol61-static-review.json")
        raise "failure adjudication changed #{id}" unless sha256(review) == decision.dig("static_review", "sha256")
      else
        before, after = [previous_validation, validation].map { |r| stdout(r).scan(/=== RESULTS ===.*?=== END RESULTS ===/m) }
        raise "corrected numerical results differ #{id}" unless !before.empty? && before == after
        measured = @benchmarks[id] || all_benchmarks.fetch(id)
        payload = measured.fetch("timing_correction")
        raise "shared measurement lacks correction #{id}" unless measured.fetch("timing_fixed")
        %w[original_source corrected_source].each do |kind|
          %w[commit digest].each { |key| raise "shared measurement source differs #{id}" unless payload.fetch(kind).fetch(key) == correction.fetch(kind).fetch(key) }
        end
      end
      history = @histories.fetch(id)
      latest = history.fetch("corrected_source")
      raise "final source history differs #{id}" unless latest.fetch("commit") == correction.dig("corrected_source", "commit") && latest.fetch("digest") == correction.dig("corrected_source", "digest")
      if (prior = old_benchmarks[id])
        raise "historical status unexpectedly changed #{id}" unless prior.fetch("success") == @benchmarks.fetch(id).fetch("success")
        if prior.fetch("timing_fixed")
          raise "initial source history lost #{id}" unless history.fetch("original_source") == prior.dig("timing_correction", "original_source")
          intermediate = history.fetch("intermediate_sources")
          raise "intermediate timing correction lost #{id}" unless intermediate == [prior.dig("timing_correction", "corrected_source")] && intermediate.first.fetch("digest") == correction.dig("original_source", "digest")
        end
      end
    end
    verify_audits!
    native_batches = catalog.fetch("campaigns").select { |c| c.fetch("validation_format") == "shared" }
    native_batches.each do |campaign|
      base = "batches/#{campaign.fetch('id')}"
      receipt = JSON.parse(File.read(File.join(@root, base, "aggregate/export.json")))
      raise "imported aggregate changed" unless receipt.fetch("csv_sha256") == sha256(File.join(@root, campaign.fetch("aggregate_csv")))
      validations = loader.call(campaign.fetch("validation_records"))
      manifest = load_yaml(File.join(@root, campaign.fetch("manifest")))
      raise "new validation scope differs" unless receipt.fetch("records") == validations.size
      manifest_digest = sha256(File.join(@root, campaign.fetch("manifest")))
      validations.each_value do |r|
        raise "new validation manifest differs" unless r.dig("metadata", "manifest_sha256") == manifest_digest &&
          r.fetch("source_commit") == campaign.fetch("source_commit") && r.fetch("source_batch") == campaign.fetch("id")
        verify_validation_logs!(r)
      end
      verify_exact_usage!(campaign, receipt)
      verify_benchmarks!(base, loader.call(campaign.fetch("benchmark_records")), manifest)
    end
    verify_benchmarks!(@base, @benchmarks, load_yaml(file("revalidation/provenance/evaluation_manifest.yaml")))
    verify_methods!
    true
  end

  def verify_validation_logs!(record)
    raise "validation metadata digest differs #{record.fetch('id')}" unless Digest::SHA256.hexdigest(YAML.dump(record.fetch("metadata"))) == record.fetch("metadata_sha256")
    record.fetch("logs").each do |name, content|
      raise "validation log digest differs #{record.fetch('id')}/#{name}" unless Digest::SHA256.hexdigest(content) == record.fetch("log_sha256").fetch(name)
    end
  end

  def verify_benchmarks!(base, records, manifest)
    directory = File.join(@root, base, "benchmark")
    evidence = read_jsonl(File.join(directory, "evidence-index.jsonl")).to_h { |r| [r.fetch("id"), r] }
    raise "native evidence scope differs" unless evidence.keys.sort == records.keys.sort
    config = load_yaml(File.join(directory, "provenance/benchmark_config.yaml"))
    config_sha = sha256(File.join(directory, "provenance/benchmark_config.yaml"))
    baseline = load_yaml(File.join(@root, "data/calibration/benchmark_config.yaml"))
    baseline.fetch("cells").each do |backend, cells|
      cells.each do |benchmark, old|
        %w[args timeout_seconds].each { |field| raise "inherited measurement setting changed" unless old.fetch(field) == config.fetch("cells").fetch(backend).fetch(benchmark).fetch(field) }
      end
    end
    amendment_sha = sha256(File.join(directory, "provenance/source_correction_amendment.yaml"))
    amendment = load_yaml(File.join(directory, "provenance/source_correction_amendment.yaml"))
    raise "shared source amendment registry differs" unless amendment.fetch("records_sha256") == sha256(file("final/corrections.jsonl"))
    full = load_yaml(File.join(directory, "benchmark_full_results.yaml"))
    raise "native full-result scope differs" unless full.keys.sort == records.keys.sort
    records.each do |id, record|
      raise "imported configuration differs #{id}" unless record.fetch("configuration_sha256") == config_sha
      if record.fetch("timing_fixed")
        raise "source amendment differs #{id}" unless record.dig("timing_correction", "source_correction_amendment_sha256") == amendment_sha
      end
      native = reconstruct_metadata(record, manifest.fetch("runs").fetch(id), evidence.fetch(id).fetch("metadata_key_order"))
      raise "native benchmark metadata differs #{id}" unless Digest::SHA256.hexdigest(YAML.dump(native)) == evidence.fetch(id).fetch("metadata_sha256")
      native_result = full.fetch(id)
      raise "canonical benchmark result differs #{id}" unless native_result[0] == record.fetch("success") &&
        (record.fetch("success") ? native_result[1] == record.fetch("metrics") : native_result[1].empty?)
      if record.fetch("success")
        raise "incomplete benchmark execution #{id}" unless record.fetch("metrics").size == 5 && record.fetch("executions").size == 6 &&
          record.fetch("executions").all? { |e| e.fetch("success") && !e.fetch("timed_out") }
      else
        raise "failed benchmark retains measurements #{id}" unless record.fetch("metrics").empty?
        evidence.fetch(id).fetch("log_sha256").each do |name, digest|
          raise "failure log differs #{id}/#{name}" unless sha256(File.join(directory, "failures", id, name)) == digest
        end
      end
    end
  end

  def reconstruct_metadata(record, info, order)
    data = { "run" => info, "pipeline_amendment_sha256" => record["pipeline_amendment_sha256"] }
    %w[args timeout_seconds configuration_sha256 wall_seconds warmup_wall_seconds all_execution_wall_seconds executions success metrics].each { |key| data[key] = record.fetch(key) }
    if record.fetch("timing_fixed")
      correction = record.fetch("timing_correction")
      data.merge!("timing_fixed" => true,
        "source_correction_amendment_sha256" => correction.fetch("source_correction_amendment_sha256"),
        "timing_fix_issue_categories" => correction.fetch("issue_categories"), "timing_fix_changed_paths" => correction.fetch("changed_paths"),
        "build_success" => correction.dig("build", "success"), "build_error" => correction.dig("build", "error"),
        "temporary_workspace" => correction.dig("build", "temporary_workspace"),
        "staged_source_content_sha256" => correction.dig("build", "staged_source_content_sha256"))
      %w[original corrected].each { |kind| %w[commit digest].each { |key| data["#{kind}_source_#{key}"] = correction.dig("#{kind}_source", key) } }
    end
    raise "native metadata field set differs" unless data.keys.sort == order.sort
    order.to_h { |key| [key, data.fetch(key)] }
  end

  def verify_exact_usage!(campaign, receipt)
    relative = campaign.fetch("exact_codex_usage")
    target = File.join(@root, relative)
    raise "exact usage input differs" unless sha256(target) == receipt.fetch("codex_usage_sha256")
    evidence = CodexUsage.load_records(target)
    rows = CSV.read(File.join(@root, campaign.fetch("aggregate_csv")), headers: true)
    raise "new exact usage coverage differs" unless rows.size == evidence.size
    rows.each do |row|
      id = "#{row.fetch('benchmark')}_#{row.fetch('model')}_#{row.fetch('par_type')}_r#{row.fetch('run')}"
      record = evidence.fetch(id)
      raise "new exact usage identity differs #{id}" unless record.fetch("batch") == campaign.fetch("id") && row["token_usage_session_id"] == record.fetch("session_id")
      { "input_tokens" => "input_tokens", "cached_tokens" => "cached_input_tokens", "output_tokens" => "output_tokens", "total_tokens" => "total_tokens" }.each do |field, key|
        raise "new exact usage count differs #{id}" unless Float(row.fetch(field)) == record.fetch("usage").fetch(key)
      end
    end
  end

  def verify_audits!
    roots = { "batches/20260929-135931/timing-audit/primary" => 295,
      "batches/20260929-135931/timing-audit/priority" => 57,
      "batches/20260929-135931/timing-audit/adjudication" => 42,
      "#{@base}/timing-audit/primary" => 425, "#{@base}/timing-audit/adjudication" => 63 }
    roots.each do |relative, expected|
      root = File.join(@root, relative)
      results = read_jsonl(File.join(root, "results.jsonl"))
      ids = results.map { |r| r.fetch("program_id") }
      raise "audit completion scope differs #{relative}" unless ids.uniq.size == expected && ids.size == expected
      manifest = load_yaml(File.join(root, "manifest.yaml"))
      artifacts = manifest.fetch("artifacts")
      { "inventory.jsonl" => "inventory_sha256", "prompt-template.txt" => "prompt_template_sha256",
        "result-schema.json" => "result_schema_sha256", "runner-snapshot.rb" => "runner_sha256" }.each do |name, key|
        next unless artifacts[key]
        raise "audit method/input changed #{relative}/#{name}" unless sha256(File.join(root, name)) == artifacts.fetch(key)
      end
    end
    qt = read_jsonl(file("timing-audit/primary/final/decisions.jsonl"))
    raise "unresolved QT boundary review" unless qt.size == 425 && qt.count { |r| r.fetch("final_verdict") == "valid" } == 378 &&
      qt.select { |r| r.fetch("timing_fix_required") }.map { |r| r.fetch("program_id") }.sort == @registry.keys.grep(/^qtclustering_/).sort
    initial = read_jsonl(File.join(@root, "batches/20260929-135931/timing-audit/primary/final/decisions.jsonl"))
    non_qt = initial.select { |r| r.fetch("timing_fix_required") && r.fetch("benchmark") != "qtclustering" }.map { |r| r.fetch("program_id") }.sort
    raise "MPI/hybrid correction scope differs" unless non_qt == (@registry.keys - @registry.keys.grep(/^qtclustering_/)).sort
  end

  def verify_methods!
    specs = {
      "#{@base}/revalidation/method/layout.json" => ["#{@base}/revalidation/provenance/evaluation_manifest.yaml", "pipeline_source"],
      "batches/20260929-135931/method/layout.json" => ["batches/20260929-135931/provenance/evaluation_manifest.yaml", "pipeline_source"],
      "batches/20260929-135931/benchmark/method/pipeline-layout.json" => ["batches/20260929-135931/benchmark/provenance/pipeline_amendment.yaml", "amended_pipeline_source"]
    }
    specs.each do |relative, (manifest_path, key)|
      files = load_yaml(File.join(@root, manifest_path)).fetch(key).fetch("files")
      layout = JSON.parse(File.read(File.join(@root, relative)))
      raise "method file set differs #{relative}" unless files.keys.sort == layout.keys.sort
      layout.each do |name, stored|
        raise "retained method digest differs #{name}" unless sha256(File.join(@root, stored)) == files.fetch(name)
      end
    end
  end

  def apply!(validations, records, rows)
    affected = validations.keys & @registry.keys
    affected.each { |id| validations[id] = @validations.fetch(id) }
    (records.keys & @benchmarks.keys).each { |id| records[id] = @benchmarks.fetch(id) }
    rows.each do |row|
      id = "#{row.fetch('benchmark')}_#{row.fetch('model')}_#{row.fetch('par_type')}_r#{row.fetch('run')}"
      next unless affected.include?(id)
      validation = validations.fetch(id)
      row["validation_status"] = VALIDATION_STAGES.take_while { |s| stages(validation).fetch(s) == true }.size.to_s
      row["validation_err_string"] = passed?(validation) ? "" : validation.fetch("result").split(/(?=Output comparison FAILED:)/, 2).last.gsub(/[\r\n]+/, " ").strip
      correction = @registry.fetch(id)
      row["timing_fixed"] = "true"
      row["timing_fix_issue_categories"] = correction.fetch("original_issue_categories").join(";")
      %w[original corrected].each do |kind|
        %w[commit digest].each { |key| row["#{kind}_source_#{key}"] = correction.fetch("#{kind}_source").fetch(key) }
        row["#{kind}_source_url"] = correction.fetch("#{kind}_source_url")
      end
      if (record = @benchmarks[id])
        row["benchmark_success"] = record.fetch("success").to_s
        row["benchmark_times"] = record.fetch("success") ? record.fetch("metrics").map { |m| m.fetch("time") }.join(";") : nil
        row["benchmark_median_time"] = record.fetch("success") ? record.fetch("metrics").map { |m| m.fetch("time") }.sort[2].to_s : nil
        row["benchmark_wall_times"] = record.fetch("wall_seconds").join(";")
        row["benchmark_config_sha256"] = record.fetch("configuration_sha256")
        row["source_correction_amendment_sha256"] = record.dig("timing_correction", "source_correction_amendment_sha256")
      end
    end
  end
end
