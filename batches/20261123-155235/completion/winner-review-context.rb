# frozen_string_literal: true
# Pre-integration comparison only. Does not alter the release, site, scores or measurements.
require "csv"
require "json"
require "yaml"
require "digest"
require "open3"
require "fileutils"
require "time"

module Gpt62WinnerContext
  module_function

  def entry(id:, cell:, times:, **attributes)
    raise "Invalid timing vector: #{id}" unless times.size == 5 && times.all? { |time| time.is_a?(Numeric) && time.finite? && time.positive? }
    { "id" => id, "cell" => cell, "times_ms" => times, "median_ms" => times.sort[2],
      "range_ms" => times.minmax }.merge(attributes.transform_keys(&:to_s))
  end

  def groups(entries)
    raise "Duplicate comparison ID" unless entries.map { |row| row.fetch("id") }.uniq.size == entries.size
    entries.group_by { |row| row.fetch("cell") }.sort.to_h.transform_values do |rows|
      rows.sort_by { |row| [row.fetch("median_ms"), row.fetch("id")] }
    end
  end

  def compare(prior, additions)
    old = groups(prior)
    combined = groups(prior + additions)
    raise "New or missing benchmark/backend cell" unless old.keys == combined.keys
    addition_ids = additions.to_h { |row| [row.fetch("id"), true] }
    combined.to_h do |cell, rows|
      winner = rows.first
      [cell, { "previous" => old.fetch(cell).first, "current" => winner,
               "new_winner" => addition_ids.key?(winner.fetch("id")),
               "top" => rows.first(8),
               "new_profiles" => rows.select { |row| addition_ids.key?(row.fetch("id")) }
                 .group_by { |row| row.fetch("model") }.transform_values(&:first) }]
    end
  end

  def historical_campaign(catalog, batch, id)
    replacement = catalog.fetch("observation_replacements", []).find do |entry|
      entry.fetch("id") == batch && entry.fetch("ids").include?(id)
    end
    direct = catalog.fetch("campaigns").find { |entry| entry.fetch("id") == batch }
    return replacement || direct if replacement || direct
    canonical = catalog.fetch("campaigns").select { |entry| entry.fetch("validation_format") == "canonical" }
    raise "Cannot identify the historical canonical campaign" unless canonical.size == 1
    canonical.first # Actual membership and source path are checked below.
  end

  def pin_review_sources(cells, artifact)
    catalog = JSON.parse(File.read(File.join(artifact, "release/catalog.json")))
    source_repo = "/home/petert/llm_para_experiments"
    validation_cache = {}
    pins = {}
    inputs = []
    cells.values.select { |cell| cell.fetch("new_winner") }.each do |cell|
      peers = (cell.fetch("top") + [cell.fetch("previous")]).uniq { |row| row.fetch("id") }
      peers.each do |peer|
        id = peer.fetch("id")
        path = peer.fetch("source_path")
        unless peer["source_commit"]
          batch = path.split("/").first
          campaign = historical_campaign(catalog, batch, id)
          pattern = campaign.fetch("validation_records")
          validations = validation_cache[pattern] ||= Dir[File.join(artifact, pattern)].sort.flat_map do |filename|
            inputs << filename
            File.readlines(filename).map { |line| JSON.parse(line) }
          end.to_h { |record| [record.fetch("id"), record] }
          validation = validations.fetch(id)
          if validation["source"]
            raise "Historical source path differs: #{id}" unless validation.dig("source", "batch") == batch && validation.dig("source", "path") == path
          else
            raise "Historical source batch differs: #{id}" unless validation.fetch("source_batch") == batch
          end
          peer["source_commit"] = validation["source_commit"] || validation.dig("source", "commit") || campaign.fetch("source_commit")
        end
        commit = peer.fetch("source_commit")
        raise "Unsafe source identity" unless commit.match?(/\A[0-9a-f]{40}\z/) && path.match?(/\A[0-9]{8}-[0-9]{6}\/[a-zA-Z0-9_.-]+\z/)
        listing, status = Open3.capture2("git", "-C", source_repo, "ls-tree", "-rz", commit, "--", path)
        raise "Cannot list pinned source: #{id}" unless status.success?
        files = listing.split("\0").filter_map do |record|
          metadata, filename = record.split("\t", 2)
          mode, type, oid = metadata.split(" ")
          next unless filename.end_with?(".cpp", ".cu", ".hpp", ".h", "/CMakeLists.txt")
          raise "Non-ordinary source blob" unless %w[100644 100755].include?(mode) && type == "blob" && filename.start_with?(path + "/")
          bytes, ok = Open3.capture2("git", "-C", source_repo, "cat-file", "blob", oid)
          raise "Cannot read pinned source" unless ok.success?
          [filename.delete_prefix(path + "/"), Digest::SHA256.hexdigest(bytes)]
        end.to_h
        raise "Incomplete source pin: #{id}" unless files.keys.any? { |name| name.end_with?(".cpp", ".cu") } && files.keys.any? { |name| File.basename(name) == "CMakeLists.txt" }
        pin = { "commit" => commit, "path" => path, "files" => files }
        raise "Conflicting source pin" if pins.key?(id) && pins.fetch(id) != pin
        pins[id] = pin
        peer["source_pin_status"] = "Pinned committed source files; not a claim of completed scientific review"
      end
    end
    [pins.sort.to_h, inputs.uniq]
  end

  def run
    evaluation = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
    artifact = "/home/petert/llm-eval-local"
    run = "/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v5"
    output = File.join(evaluation, "winner-review-context-preintegration.json")
    raise "Winner context already exists" if File.exist?(output)
    completion_path = File.join(evaluation, "benchmark-completion-review.json")
    completion = JSON.parse(File.read(completion_path))
    raise "Benchmark evidence not complete" unless completion.fetch("verification") == "passed" && completion.fetch("completed") == 439
    baseline_commit, status = Open3.capture2("git", "-C", artifact, "rev-parse", "HEAD")
    raise "Cannot pin baseline" unless status.success?
    baseline_commit = baseline_commit.strip
    baseline_paths = %w[release/scored_results.csv release/winners.json release/catalog.json]
    baseline_paths.each do |relative|
      bytes, ok = Open3.capture2("git", "-C", artifact, "show", "#{baseline_commit}:#{relative}")
      raise "Baseline is not the committed release: #{relative}" unless ok.success? && bytes.b == File.binread(File.join(artifact, relative))
    end
    csv = CSV.read(File.join(artifact, "release/scored_results.csv"), headers: true)
    prior = csv.filter_map do |row|
      next unless row.fetch("benchmark_success") == "true"
      raise "Ineligible baseline observation" unless Integer(row.fetch("validation_status")) == 5
      id = "#{row.fetch('benchmark')}_#{row.fetch('model')}_#{row.fetch('par_type')}_r#{row.fetch('run')}"
      result = entry(id: id, cell: "#{row.fetch('benchmark')}/#{row.fetch('par_type')}",
        times: row.fetch("benchmark_times").split(";").map { |time| Float(time) },
        model: row.fetch("model"), source_path: row.fetch("source_path"), timing_fixed: row.fetch("timing_fixed") == "true",
        source_commit: row["corrected_source_commit"].to_s.empty? ? nil : row["corrected_source_commit"],
        source_pin_status: "Resolve exact historical source via retained campaign/overlay evidence before source review")
      raise "Baseline median mismatch" unless result.fetch("median_ms") == Float(row.fetch("benchmark_median_time"))
      result
    end
    old_groups = groups(prior)
    published = JSON.parse(File.read(File.join(artifact, "release/winners.json")))
    raise "Baseline winner coverage differs" unless published.size == 44 && published.map { |row| row.fetch("cell") }.sort == old_groups.keys
    published.each do |row|
      candidate = old_groups.fetch(row.fetch("cell")).first
      raise "Baseline winner differs" unless %w[id median_ms times_ms].all? { |key| candidate.fetch(key) == row.fetch(key) }
    end
    native_path = File.join(run, "benchmark/benchmark_full_results.yaml")
    native = YAML.safe_load_file(native_path, aliases: true)
    raise "Native benchmark coverage changed" unless native.size == completion.fetch("completed") && native.count { |_, record| record.first == true } == completion.fetch("successful")
    commit_path = File.join(evaluation, "correction-commit.json")
    commits = JSON.parse(File.read(commit_path))
    corrected_ids = File.readlines("/home/petert/llm_timing_fixes/20261125-gpt62-astra-sol-medium-final/correction-ids.txt", chomp: true)
    manifest_path = File.join(run, "evaluation_manifest.yaml")
    manifest = YAML.safe_load_file(manifest_path)
    metadata_paths = []
    additions = native.filter_map do |id, record|
      next unless record.first == true
      descriptor = manifest.fetch("runs").fetch(id)
      raise "Unexpected new model" unless %w[gpt-6.2-astra-medium gpt-6.2-sol-medium].include?(descriptor.fetch("model"))
      path = File.join(run, "benchmark", id, "benchmark_metadata.yaml")
      metadata_paths << path
      metadata = YAML.safe_load_file(path)
      raise "Native measurement vector differs" unless metadata.fetch("success") && metadata.fetch("metrics") == record.last
      entry(id: id, cell: "#{descriptor.fetch('benchmark')}/#{descriptor.fetch('par_type')}",
        times: record.last.map { |metric| metric.fetch("time") }, model: descriptor.fetch("model"),
        source_path: "20261123-155235/#{id}", timing_fixed: corrected_ids.include?(id),
        source_commit: commits.fetch(corrected_ids.include?(id) ? "corrected_commit" : "original_commit"),
        args: metadata.fetch("args"), source_pin_status: "Exact generation/correction commit; pin source files before source review")
    end
    cells = compare(prior, additions)
    pins, validation_inputs = pin_review_sources(cells, artifact)
    selection_path = File.join(evaluation, "default-visible-set-selection.json")
    selection = JSON.parse(File.read(selection_path))
    raise "Default-set discussion unresolved" unless selection.fetch("publication_discussion_resolved")
    inputs = baseline_paths.map { |relative| File.join(artifact, relative) } +
      [completion_path, native_path, commit_path, manifest_path, selection_path] + metadata_paths + validation_inputs
    report = {
      "schema_version" => 1, "created_at" => Time.now.utc.iso8601, "baseline_commit" => baseline_commit,
      "purpose" => "Frozen pre-integration winner comparison. No release/site edits, rescore, new executions or validity changes.",
      "all_models_included" => true, "default_visible_model_set_decided" => true,
      "prior_observations" => csv.size, "prior_successful" => prior.size, "new_successful" => additions.size,
      "new_winner_ids" => cells.values.select { |cell| cell.fetch("new_winner") }.map { |cell| cell.fetch("current").fetch("id") },
      "cells" => cells, "source_pins" => pins,
      "input_sha256" => inputs.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
      "script_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
      "review_policy" => "Review every new cell winner; concise close-group context for near ties, deeper analysis for separated outliers without a fixed percentage threshold. Sample ranges are descriptive, not confidence intervals."
    }
    File.write(output, JSON.pretty_generate(report) + "\n")
    FileUtils.cp(__FILE__, evaluation)
    puts JSON.pretty_generate(report.slice("created_at", "baseline_commit", "prior_observations", "new_successful", "new_winner_ids"))
  end
end

Gpt62WinnerContext.run if $PROGRAM_NAME == __FILE__
