# frozen_string_literal: true

require_relative "artifact_common"
require_relative "batch_verification"
require_relative "../method/timing-audit/scoring_threshold_review"

# The release is a view over immutable campaigns, not a second copy of their logs.
class CurrentRelease
  include LocalEvalArtifact
  include BatchVerification
  def initialize(root)
    @root = File.expand_path(root)
    @catalog = JSON.parse(File.read(path("release/catalog.json")))
  end

  def path(relative)
    raise "unsafe release path #{relative}" if Pathname.new(relative).absolute? || relative.split("/").include?("..")
    File.join(@root, relative)
  end

  def self.id(row)
    "#{row.fetch('benchmark')}_#{row.fetch('model')}_#{row.fetch('par_type')}_r#{row.fetch('run')}"
  end

  def self.score(row, cell)
    base = Integer(row.fetch("validation_status"))
    return base unless row["benchmark_success"] == "true"
    time = Float(row.fetch("benchmark_median_time"))
    base + if time == cell.fetch("fastest") then 5
           elsif time <= cell.fetch("top") then 4
           elsif time <= cell.fetch("great") then 3
           elsif time <= cell.fetch("good") then 2
           else 1 end
  end

  def load_records(pattern)
    files = Dir.glob(path(pattern)).sort
    raise "empty record selection #{pattern}" if files.empty?
    files.flat_map { |file| LocalEvalArtifact.read_jsonl(file) }.to_h do |record|
      [record.fetch("id"), record]
    end.tap do |map|
      count = files.sum { |file| File.foreach(file).count }
      raise "duplicate record IDs in #{pattern}" unless count == map.size
    end
  end

  def groups(rows)
    rows.select { |row| row["benchmark_success"] == "true" }
        .group_by { |row| "#{row.fetch('benchmark')}/#{row.fetch('par_type')}" }
        .sort.to_h.transform_values do |entries|
      entries.map do |row|
        { "id" => self.class.id(row), "median_time" => Float(row.fetch("benchmark_median_time")),
          "times" => row.fetch("benchmark_times").split(";").map { |v| Float(v) } }
      end.sort_by { |entry| [entry.fetch("median_time"), entry.fetch("id")] }
    end
  end

  def build
    inputs = {}
    headers = []
    campaigns = @catalog.fetch("campaigns")
    benchmarks = {}
    rows = campaigns.flat_map do |campaign|
      relative = campaign.fetch("aggregate_csv")
      inputs[relative] = sha256(path(relative))
      table = CSV.read(path(relative), headers: true)
      headers |= table.headers
      validations = load_records(campaign.fetch("validation_records"))
      original_validations = validations.dup
      corrections = {}
      if campaign["corrected_validation_records"]
        corrections = load_records(campaign.fetch("corrected_validation_records"))
        raise "correction outside validation campaign" unless (corrections.keys - validations.keys).empty?
        validations.merge!(corrections)
      end
      records = load_records(campaign.fetch("benchmark_records"))
      verify_batch(campaign, original_validations, corrections, records) if campaign.fetch("validation_format") == "batch"
      raise "overlapping campaign benchmark IDs" unless (benchmarks.keys & records.keys).empty?
      benchmarks.merge!(records)
      raise "aggregate/validation IDs differ" unless table.map { |r| self.class.id(r) }.sort == validations.keys.sort
      native = table.map(&:to_h)
      config = LocalEvalArtifact.load_yaml(path(campaign.fetch("benchmark_config")))
      config_digest = sha256(path(campaign.fetch("benchmark_config")))
      native.each do |row|
        id = self.class.id(row)
        validation = validations.fetch(id)
        stages = validation["stages"] || validation.fetch("metadata").fetch("stages")
        passed = LocalEvalArtifact::VALIDATION_STAGES.take_while { |stage| stages[stage] == true }.size
        raise "validation score mismatch #{id}" unless passed == Integer(row.fetch("validation_status"))
        record = records[id]
        raise "benchmark eligibility mismatch #{id}" unless (passed == 5) == !record.nil?
        if record
          raise "benchmark success mismatch #{id}" unless record.fetch("success").to_s == row["benchmark_success"]
          raise "timing-fix mismatch #{id}" unless record.fetch("timing_fixed").to_s == row["timing_fixed"]
          raise "configuration mismatch #{id}" unless record.fetch("configuration_sha256") == row["benchmark_config_sha256"]
          raise "configuration digest mismatch #{id}" unless record.fetch("configuration_sha256") == config_digest
          cell = config.fetch("cells").fetch(row.fetch("par_type")).fetch(row.fetch("benchmark"))
          raise "measurement arguments differ #{id}" unless record.fetch("args") == cell.fetch("args")
          raise "measurement timeout differs #{id}" unless record.fetch("timeout_seconds") == cell.fetch("timeout_seconds")
          if record.fetch("success")
            executions = record.fetch("executions")
            raise "incomplete executions #{id}" unless executions.size == 6 && executions.all? { |execution| execution.fetch("success") && !execution.fetch("timed_out") }
            times = record.fetch("metrics").map { |metric| metric.fetch("time") }
            raise "invalid times #{id}" unless times.size == 5 && times.all? { |t| t.is_a?(Numeric) && t.positive? && t.finite? }
            raise "measurement vector mismatch #{id}" unless times == row.fetch("benchmark_times").split(";").map { |v| Float(v) }
            raise "median mismatch #{id}" unless times.sort[2] == Float(row.fetch("benchmark_median_time"))
          end
        end
        # Source paths in the release are repository relative; raw campaign records retain native paths.
        row["source_path"] = "#{row.fetch('source_batch')}/#{id}"
      end
      native
    end
    ids = rows.map { |row| self.class.id(row) }
    raise "overlapping campaign IDs" unless ids.uniq.size == ids.size
    rows.sort_by! { |row| self.class.id(row) }
    expected = @catalog.fetch("expected")
    actual = {
      "runs" => rows.size, "models" => rows.map { |r| r.fetch("model") }.uniq.size,
      "benchmarked" => benchmarks.size, "successful" => benchmarks.values.count { |r| r.fetch("success") },
      "timing_fixed" => rows.count { |r| r["timing_fixed"] == "true" }
    }
    raise "release count mismatch #{actual.inspect}" unless actual == expected
    raise "unbalanced model/cell repetitions" unless rows.group_by { |r| [r["model"], r["benchmark"], r["par_type"]] }.values.all? { |rs| rs.map { |r| r["run"] }.sort == %w[1 2 3 4 5] }
    baseline = LocalEvalArtifact.load_yaml(path(campaigns.first.fetch("benchmark_config")))
    campaigns.drop(1).each do |campaign|
      config = LocalEvalArtifact.load_yaml(path(campaign.fetch("benchmark_config")))
      baseline.fetch("cells").each do |backend, cells|
        cells.each do |benchmark, old|
          current = config.fetch("cells").fetch(backend).fetch(benchmark)
          %w[args timeout_seconds].each { |field| raise "calibration changed #{benchmark}/#{backend}" unless old.fetch(field) == current.fetch(field) }
        end
      end
    end
    grouped = groups(rows)
    reviewer = ScoringThresholdReview.new(run_dir: @root)
    cells = grouped.transform_values { |entries| reviewer.send(:review_cell, entries) }
    # Regression gate: the same scoring formula must reproduce every historic score.
    old_rows = CSV.read(path("data/scoring/scored_results.csv"), headers: true)
    old_cells = LocalEvalArtifact.load_yaml(path("data/scoring/local_scoring_threshold_review.yaml")).fetch("cells")
    old_rows.each do |row|
      raise "historical score regression #{self.class.id(row)}" unless self.class.score(row, old_cells.fetch("#{row['benchmark']}/#{row['par_type']}")) == Integer(row.fetch("overall_score"))
    end
    headers.delete("overall_score")
    headers << "overall_score"
    scored = CSV.generate do |csv|
      csv << headers
      rows.each do |row|
        row["overall_score"] = self.class.score(row, cells.fetch("#{row['benchmark']}/#{row['par_type']}"))
        csv << headers.map { |header| row[header] }
      end
    end
    thresholds = CSV.generate do |csv|
      csv << %w[bench type top great good reviewed]
      cells.each { |key, c| csv << [*key.split("/"), c["top"], c["great"], c["good"], true] }
    end
    old_by_id = old_rows.to_h { |row| [self.class.id(row), row] }
    changes = CSV.generate do |csv|
      csv << %w[id previous_score current_score reason]
      rows.each do |row|
        id = self.class.id(row)
        old = old_by_id[id]
        next unless old && Integer(old["overall_score"]) != row["overall_score"]
        csv << [id, old["overall_score"], row["overall_score"], "joint distribution rescore; measurements unchanged"]
      end
    end
    old_groups = groups(old_rows)
    winners = grouped.map do |key, entries|
      old = old_groups.fetch(key).first
      winner = entries.first
      record = benchmarks.fetch(winner.fetch("id"))
      { "cell" => key, "id" => winner.fetch("id"), "median_ms" => winner.fetch("median_time"),
        "times_ms" => winner.fetch("times"), "args" => record.fetch("args"), "timing_fixed" => record.fetch("timing_fixed"),
        "previous_id" => old.fetch("id"), "previous_median_ms" => old.fetch("median_time"), "previous_times_ms" => old.fetch("times"),
        "previous_over_current" => old.fetch("median_time") / winner.fetch("median_time"),
        "new_winner" => old.fetch("id") != winner.fetch("id") }
    end
    # Pin every input record file and campaign configuration, without copying their contents.
    campaigns.each do |campaign|
      %w[validation_records corrected_validation_records benchmark_records benchmark_config manifest].each do |field|
        next unless campaign[field]
        Dir.glob(path(campaign.fetch(field))).sort.each { |p| inputs[relative_path(@root, p)] = sha256(p) }
      end
    end
    campaigns.select { |c| c.fetch("validation_format") == "batch" }.each do |campaign|
      # Redundant checksum manifests are checked separately; all their actual inputs are pinned here.
      Dir.glob(path("batches/#{campaign.fetch('id')}/**/*")).sort.select { |p| File.file?(p) && File.basename(p) != "checksums.sha256" }.each { |p| inputs[relative_path(@root, p)] = sha256(p) }
    end
    %w[release/catalog.json tools/current_release.rb tools/batch_verification.rb method/timing-audit/scoring_threshold_review.rb data/scoring/scored_results.csv data/scoring/local_scoring_threshold_review.yaml].each { |p| inputs[p] = sha256(path(p)) }
    metadata = {
      "schema_version" => 1, "generated_at" => @catalog.fetch("generated_at"), "counts" => actual,
      "scored_csv_sha256" => Digest::SHA256.hexdigest(scored), "thresholds_sha256" => Digest::SHA256.hexdigest(thresholds),
      "inputs" => inputs.sort.to_h, "measurement_reruns" => 0,
      "method" => "Unchanged historic log-natural-break review and 0-10 scoring, applied jointly to all campaigns."
    }
    {
      "release/scored_results.csv" => scored,
      "release/local_scoring_thresholds.csv" => thresholds,
      "release/local_scoring_threshold_review.yaml" => YAML.dump({ "schema_version" => 1, "reviewed" => true, "cells" => cells }),
      "release/scoring_metadata.yaml" => YAML.dump(metadata),
      "release/historical_score_changes.csv" => changes,
      "release/winners.json" => JSON.pretty_generate(winners) + "\n"
    }
  end

  def run(check: false, require_reviews: false)
    outputs = build
    outputs.each do |relative, content|
      if check
        raise "stale release output #{relative}" unless File.file?(path(relative)) && File.binread(path(relative)) == content
      else
        FileUtils.mkdir_p(File.dirname(path(relative)))
        File.binwrite(path(relative), content)
      end
    end
    if require_reviews
      JSON.parse(outputs.fetch("release/winners.json")).each do |winner|
        note = path("analysis/notes/individual/#{winner.fetch('id')}.md")
        raise "winner review missing #{winner.fetch('id')}" unless File.file?(note)
      end
    end
    puts "Current release #{check ? 'verified' : 'built'}: #{@catalog.fetch('expected').inspect}"
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"
  options = { check: false, require_reviews: false }
  root = File.expand_path("..", __dir__)
  OptionParser.new do |parser|
    parser.on("--root=PATH") { |value| root = value }
    parser.on("--check") { options[:check] = true }
    parser.on("--require-reviews") { options[:require_reviews] = true }
  end.parse!
  CurrentRelease.new(root).run(**options)
end
