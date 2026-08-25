#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "optparse"

class TimingCorrectionAnalysis
  DETAIL_HEADERS = %w[
    id benchmark model backend repetition issue_categories prior_success
    corrected_success prior_median_time_ms corrected_median_time_ms median_time_ratio
    corrected_median_wall_seconds wall_to_reported_time_ratio corrected_repeat_spread_ratio
    corrected_under_200ms
    prior_overall_score corrected_overall_score score_delta original_source_url
    corrected_source_url
  ].freeze
  SUMMARY_HEADERS = %w[
    dimension value corrections corrected_successes corrected_failures comparable_times
    median_time_ratio p10_time_ratio p25_time_ratio p75_time_ratio p90_time_ratio
    min_time_ratio max_time_ratio score_increases score_decreases score_unchanged
    median_score_delta
  ].freeze

  def initialize(root)
    @root = File.expand_path(root)
    @tables = File.join(@root, "analysis", "tables")
  end

  def run
    comparisons = read_jsonl("data/timing-audit/rerun-comparison.jsonl")
    decisions = read_jsonl("data/timing-audit/static-audit/final/decisions.jsonl")
                .to_h { |record| [record.fetch("program_id"), record] }
    corrections = read_jsonl("data/timing-audit/corrections/final/corrections.jsonl")
                  .to_h { |record| [record.fetch("program_id"), record] }
    scores = read_scores

    details = comparisons.map do |comparison|
      id = comparison.fetch("id")
      decision = decisions.fetch(id)
      correction = corrections.fetch(id)
      corrected_score = scores.fetch(id)
      prior_score = Integer(decision.fetch("overall_score"))
      corrected_metrics = comparison.dig("corrected", "metrics")
      corrected_times = corrected_metrics.map { |metric| Float(metric.fetch("time")) }.sort
      corrected_median = comparison.dig("corrected", "median_time_ms")
      corrected_wall = comparison.dig("corrected", "median_wall_seconds")
      {
        "id" => id,
        "benchmark" => comparison.fetch("benchmark"),
        "model" => comparison.fetch("model"),
        "backend" => comparison.fetch("backend"),
        "repetition" => comparison.fetch("repetition"),
        "issue_categories" => correction.fetch("original_issue_categories").join(";"),
        "prior_success" => comparison.dig("prior", "success"),
        "corrected_success" => comparison.dig("corrected", "success"),
        "prior_median_time_ms" => comparison.dig("prior", "median_time_ms"),
        "corrected_median_time_ms" => corrected_median,
        "median_time_ratio" => comparison["median_time_ratio"],
        "corrected_median_wall_seconds" => corrected_wall,
        "wall_to_reported_time_ratio" => corrected_median && corrected_wall ? corrected_wall * 1_000.0 / corrected_median : nil,
        "corrected_repeat_spread_ratio" => corrected_times.size == 5 ? corrected_times.fetch(3) / corrected_times.fetch(1) : nil,
        "corrected_under_200ms" => corrected_median ? corrected_median < 200.0 : nil,
        "prior_overall_score" => prior_score,
        "corrected_overall_score" => corrected_score,
        "score_delta" => corrected_score - prior_score,
        "original_source_url" => comparison.fetch("original_source_url"),
        "corrected_source_url" => comparison.fetch("corrected_source_url")
      }
    end.sort_by { |record| record.fetch("id") }

    audit_score_changes = decisions.values.filter_map do |decision|
      id = decision.fetch("program_id")
      prior_score = Integer(decision.fetch("overall_score"))
      corrected_score = scores.fetch(id)
      next if prior_score == corrected_score

      {
        "id" => id,
        "benchmark" => decision.fetch("benchmark"),
        "model" => decision.fetch("model"),
        "backend" => decision.fetch("par_type"),
        "repetition" => decision.fetch("run"),
        "timing_fixed" => decision.fetch("timing_fix_required"),
        "prior_overall_score" => prior_score,
        "corrected_overall_score" => corrected_score,
        "score_delta" => corrected_score - prior_score
      }
    end.sort_by { |record| record.fetch("id") }

    FileUtils.mkdir_p(@tables)
    write_csv(File.join(@tables, "timing-correction-details.csv"), DETAIL_HEADERS, details)
    summaries = build_summaries(details)
    write_csv(File.join(@tables, "timing-correction-summary.csv"), SUMMARY_HEADERS, summaries)
    issue_counts = build_issue_counts(details)
    write_csv(
      File.join(@tables, "timing-correction-issue-counts.csv"),
      %w[issue_category records],
      issue_counts
    )
    write_csv(
      File.join(@tables, "timing-audit-score-changes.csv"),
      %w[
        id benchmark model backend repetition timing_fixed prior_overall_score
        corrected_overall_score score_delta
      ],
      audit_score_changes
    )
    File.write(
      File.join(@root, "analysis", "timing-correction-report.md"),
      report(details, summaries, issue_counts, audit_score_changes),
      mode: "wb"
    )

    puts "Wrote #{details.size} timing-correction detail rows and #{summaries.size} summary rows"
  end

  private

  def read_jsonl(relative)
    File.foreach(File.join(@root, relative), chomp: true).map { |line| JSON.parse(line) }
  end

  def read_scores
    CSV.foreach(File.join(@root, "data", "scoring", "scored_results.csv"), headers: true).to_h do |row|
      id = "#{row.fetch('benchmark')}_#{row.fetch('model')}_#{row.fetch('par_type')}_r#{row.fetch('run')}"
      [id, Integer(row.fetch("overall_score"), 10)]
    end
  end

  def build_summaries(details)
    groups = [["all", "all", details]]
    %w[backend benchmark model].each do |dimension|
      details.group_by { |record| record.fetch(dimension) }.sort.each do |value, records|
        groups << [dimension, value, records]
      end
    end
    details.group_by { |record| [record.fetch("benchmark"), record.fetch("backend")] }
           .sort.each do |(benchmark, backend), records|
      groups << ["benchmark_backend", "#{benchmark}/#{backend}", records]
    end

    groups.map do |dimension, value, records|
      ratios = records.filter_map { |record| finite_number(record["median_time_ratio"]) }.sort
      score_deltas = records.map { |record| record.fetch("score_delta") }.sort
      {
        "dimension" => dimension,
        "value" => value,
        "corrections" => records.size,
        "corrected_successes" => records.count { |record| record.fetch("corrected_success") },
        "corrected_failures" => records.count { |record| !record.fetch("corrected_success") },
        "comparable_times" => ratios.size,
        "median_time_ratio" => percentile(ratios, 0.5),
        "p10_time_ratio" => percentile(ratios, 0.10),
        "p25_time_ratio" => percentile(ratios, 0.25),
        "p75_time_ratio" => percentile(ratios, 0.75),
        "p90_time_ratio" => percentile(ratios, 0.90),
        "min_time_ratio" => ratios.first,
        "max_time_ratio" => ratios.last,
        "score_increases" => score_deltas.count(&:positive?),
        "score_decreases" => score_deltas.count(&:negative?),
        "score_unchanged" => score_deltas.count(&:zero?),
        "median_score_delta" => percentile(score_deltas, 0.5)
      }
    end
  end

  def build_issue_counts(details)
    counts = Hash.new(0)
    details.each do |record|
      record.fetch("issue_categories").split(";").each { |category| counts[category] += 1 }
    end
    counts.sort_by { |category, count| [-count, category] }.map do |category, count|
      { "issue_category" => category, "records" => count }
    end
  end

  def finite_number(value)
    return nil if value.nil?

    number = Float(value)
    number if number.finite?
  end

  def percentile(values, fraction)
    return nil if values.empty?
    return values.first if values.size == 1

    position = fraction * (values.size - 1)
    lower = position.floor
    upper = position.ceil
    return values[lower] if lower == upper

    values[lower] + (values[upper] - values[lower]) * (position - lower)
  end

  def write_csv(path, headers, records)
    CSV.open(path, "wb", write_headers: true, headers: headers) do |csv|
      records.each { |record| csv << headers.map { |header| record[header] } }
    end
  end

  def report(details, summaries, issue_counts, audit_score_changes)
    overall = summaries.find { |record| record.fetch("dimension") == "all" }
    changed = details.count { |record| record.fetch("score_delta") != 0 }
    short = details.count { |record| record.fetch("corrected_under_200ms") }
    setup_dominated = details.count do |record|
      ratio = record.fetch("wall_to_reported_time_ratio")
      ratio && ratio > 10.0
    end
    <<~MARKDOWN
      # Timing-correction impact

      This report is generated from the versioned timing audit, scoped-rerun comparison,
      and final scored dataset. It analyzes only the 587 programs whose static timing
      review required a timing-only source correction; it does not reinterpret validation.

      - Corrected benchmark successes: #{overall.fetch("corrected_successes")}/#{overall.fetch("corrections")}
      - Corrected benchmark failures: #{overall.fetch("corrected_failures")}
      - Comparable old/new median timings: #{overall.fetch("comparable_times")}
      - Median corrected/original reported-time ratio: #{format_number(overall.fetch("median_time_ratio"))}
      - Scores changed after corrected timing: #{changed}/#{details.size}
      - Score increases / decreases: #{overall.fetch("score_increases")} / #{overall.fetch("score_decreases")}
      - Audited MPI/hybrid scores changed after re-thresholding: #{audit_score_changes.size}/1,615
        (#{audit_score_changes.count { |record| record.fetch("timing_fixed") }} timing-fixed,
        #{audit_score_changes.count { |record| !record.fetch("timing_fixed") }} unchanged-source programs)
      - Corrected medians below 200 ms: #{short}/#{details.size}
      - Corrected runs with median wall time over 10x reported compute time: #{setup_dominated}/#{details.size}

      The ratio is descriptive, not a correction factor: the original value can be a
      rank-local duration and therefore need not have a stable mathematical relationship
      to the corrected maximum completed-rank duration. See
      `tables/timing-correction-summary.csv` for benchmark/backend/model groupings,
      `tables/timing-correction-details.csv` for per-program source links and score
      changes, `tables/timing-audit-score-changes.csv` for every score affected by the
      corrected cell distributions, and `tables/timing-correction-issue-counts.csv` for
      issue categories.

      The detail table retains repetition-spread and wall-to-reported-time ratios. These
      expose short or setup-dominated measurements—most visibly some Black-Scholes MPI
      programs—whose fine ordering should not be overinterpreted. Scoring boundaries
      use a per-cell repetition-noise floor, so those observations remain grouped unless
      an adjacent performance gap exceeds the measured noise.

      Most frequent static issue category: #{issue_counts.first.fetch("issue_category")}
      (#{issue_counts.first.fetch("records")} records).
    MARKDOWN
  end

  def format_number(value)
    value.nil? ? "not available" : format("%.6g", value)
  end
end

options = { root: File.expand_path("../..", __dir__) }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby analysis/src/timing_correction_analysis.rb [--root=PATH]"
  parser.on("--root=PATH", "Artifact repository root") { |value| options[:root] = value }
end.parse!

TimingCorrectionAnalysis.new(options.fetch(:root)).run
