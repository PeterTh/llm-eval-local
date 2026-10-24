# frozen_string_literal: true
require_relative "artifact_common"

# A current-data view over separately verified native batches. Replaced attempts
# remain archival evidence; only the explicitly listed IDs enter the view anew.
class ObservationReplacements
  include LocalEvalArtifact
  attr_reader :campaigns

  def initialize(reader, campaigns)
    @reader, @campaigns = reader, campaigns
    @entries, @by_id = {}, {}
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(LocalEvalArtifact.canonical_json_for_digest(value))
  end

  def verify!
    @entries, @by_id = {}, {}
    @campaigns.each do |campaign|
      batch = campaign.fetch("id")
      raise "multiple replacement sets for one batch" if @entries.key?(batch)
      base = campaign.fetch("evidence_root")
      raise "unsafe replacement evidence root" unless base.start_with?("batches/#{batch}/replacements/")
      ids = campaign.fetch("ids")
      raise "invalid replacement IDs" unless ids == ids.uniq.sort && !ids.empty?
      original = @reader.load_records(campaign.fetch("validation_records"))
      corrected = @reader.load_records(campaign.fetch("corrected_validation_records"))
      records = @reader.load_records(campaign.fetch("benchmark_records"))
      rows = CSV.read(@reader.path(campaign.fetch("aggregate_csv")), headers: true).map(&:to_h)
      raise "replacement scope differs" unless original.keys.sort == ids &&
        rows.map { |r| CurrentRelease.id(r) }.sort == ids &&
        rows.all? { |r| r.fetch("source_batch") == batch } &&
        (corrected.keys - ids).empty? && (records.keys - ids).empty?
      @reader.verify_batch(campaign, original, corrected, records)
      config_path = @reader.path(campaign.fetch("benchmark_config"))
      config = LocalEvalArtifact.load_yaml(config_path)
      baseline = LocalEvalArtifact.load_yaml(@reader.path("data/calibration/benchmark_config.yaml"))
      baseline.fetch("cells").each do |backend, cells|
        cells.each do |benchmark, old|
          %w[args timeout_seconds].each do |field|
            raise "replacement calibration changed" unless old.fetch(field) == config.fetch("cells").fetch(backend).fetch(benchmark).fetch(field)
          end
        end
      end
      guard = JSON.parse(File.read(@reader.path("#{base}/release-guard.json")))
      raise "replacement guard scope differs" unless guard.fetch("ids") == ids && guard.fetch("batch") == batch
      @entries[batch] = { campaign: campaign, rows: rows, validations: original.merge(corrected),
        records: records, guard: guard, configuration: [config, LocalEvalArtifact.sha256(config_path)] }
      ids.each do |id|
        raise "overlapping observation replacement" if @by_id.key?(id)
        @by_id[id] = @entries.fetch(batch)
      end
    end
  end

  def apply!(campaign, validations, records, rows)
    entry = @entries[campaign.fetch("id")]
    return unless entry
    ids = entry.fetch(:campaign).fetch("ids")
    indexed = rows.to_h { |row| [CurrentRelease.id(row), row] }
    raise "replacement outside original campaign" unless (ids - indexed.keys).empty?
    before = { "rows" => indexed, "validations" => validations, "benchmarks" => records }
    guard = entry.fetch(:guard)
    raise "replacement baseline changed" unless self.class.digest(before) == guard.fetch("prior_sha256")
    unaffected = before.transform_values { |data| data.reject { |id, _| ids.include?(id) } }
    raise "unrelated observations changed" unless self.class.digest(unaffected) == guard.fetch("unaffected_sha256") &&
      unaffected.fetch("rows").size == guard.fetch("unaffected_observations")
    ids.each { |id| records.delete(id) }
    validations.merge!(entry.fetch(:validations))
    records.merge!(entry.fetch(:records))
    replacements = entry.fetch(:rows).to_h { |row| [CurrentRelease.id(row), row] }
    rows.map! { |row| replacements.fetch(CurrentRelease.id(row), row) }
    after = { "rows" => rows.to_h { |row| [CurrentRelease.id(row), row] }, "validations" => validations, "benchmarks" => records }
    raise "replacement altered unrelated data" unless self.class.digest(after.transform_values { |data| data.reject { |id, _| ids.include?(id) } }) == guard.fetch("unaffected_sha256")
  end

  def configuration(id)
    @by_id[id]&.fetch(:configuration)
  end
end
