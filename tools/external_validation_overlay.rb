# frozen_string_literal: true

require_relative "artifact_common"
require_relative "supplemental_validation_registry"
require_relative "validation_sweep_receipt"
require_relative "../method/external-validation/tools/timing_audit/lib/external_validation_exclusions"

# A derived eligibility view; archived native validation and timings are not edited.
class ExternalValidationOverlay
  include LocalEvalArtifact
  attr_reader :registry, :applied_ids

  def initialize(reader, configuration)
    @reader, @configuration = reader, configuration
    export_path = reader.path(File.join(File.dirname(configuration.fetch("registry")), "export.json"))
    raise "External-validation export receipt differs" unless sha256(export_path) == configuration.fetch("export_sha256")
    export = JSON.parse(File.read(export_path))
    export.fetch("files_sha256").each do |relative, digest|
      file = reader.path(File.join(File.dirname(configuration.fetch("registry")), relative))
      raise "Supplemental evidence changed: #{relative}" unless sha256(file) == digest
    end
    registry_path = reader.path(configuration.fetch("registry"))
    schema = JSON.parse(File.read(registry_path)).fetch("schema_version")
    @registry = (schema == 1 ? ExternalValidationExclusions : SupplementalValidationRegistry).new(registry_path)
    raise "External-validation registry digest differs" unless @registry.digest == configuration.fetch("registry_sha256")
    @applied_ids = configuration.fetch("applied_ids")
    unless @applied_ids == @applied_ids.uniq.sort && (@applied_ids - @registry.records.keys).empty?
      raise "Invalid external-validation release scope"
    end
    @evidence = read_jsonl(reader.path(configuration.fetch("records"))).each_with_index.to_h { |record, i| [record.fetch("id"), [record, i + 1]] }
    @registry.records.each do |id, exclusion|
      record = @evidence.fetch(id).first
      unless record.fetch("result") == exclusion.fetch("result") && record.fetch("result_sha256") == exclusion.fetch("result_sha256") &&
          record.fetch("logs").fetch("stdout") == exclusion.fetch("stdout")
        raise "External-validation release evidence differs: #{id}"
      end
    end
  end

  def excluded?(id) = @applied_ids.include?(id)

  def case_id = @registry.data.fetch("case").fetch("id")

  def reference_stdout(case_id)
    raise "Unknown supplemental validation case: #{case_id}" unless self.case_id == case_id
    @registry.data.fetch("reference").fetch("stdout")
  end

  def excluded_ids(campaign)
    @applied_ids.select do |id|
      record = @registry.records.fetch(id)
      record.fetch("source_path").start_with?("#{campaign.fetch('id')}/") && record.fetch("source_commit") == campaign.fetch("source_commit")
    end
  end

  def apply!(rows, benchmarks, sources, headers, inputs)
    present = rows.map { |row| CurrentRelease.id(row) }
    raise "External-validation release coverage differs" unless (@registry.records.keys & present).sort == @applied_ids
    rows.each do |row|
      id = CurrentRelease.id(row)
      next unless excluded?(id)
      exclusion = @registry.records.fetch(id)
      unless sources.fetch(id) == exclusion.fetch("source_commit") && row.fetch("source_path") == exclusion.fetch("source_path") &&
          row.fetch("validation_status") == "5"
        raise "External-validation effective source or prior status differs: #{id}"
      end
      row["validation_status"] = "4"
      row["validation_err_string"] = @registry.reason(id)
      row.keys.grep(/\Abenchmark_/).each { |key| row[key] = nil }
      row["external_validation_case"] = @registry.data.fetch("case").fetch("id")
      row["external_validation_evidence"] = "#{@configuration.fetch('records')}#L#{@evidence.fetch(id).last}"
      benchmarks.delete(id)
    end
    headers.concat(%w[external_validation_case external_validation_evidence]).uniq!
    root = File.dirname(@configuration.fetch("registry"))
    regular_files(@reader.path(root)).each { |file| inputs[relative_path(@reader.path("."), file)] = sha256(file) }
    %w[tools/external_validation_overlay.rb method/external-validation/validation_helper.rb
      method/external-validation/tools/timing_audit/lib/external_validation_exclusions.rb
      tools/supplemental_validation_registry.rb method/validation-strengthening/comparison_policy.rb
      method/validation-strengthening/shape_validation_cases.rb].each do |file|
      inputs[file] = sha256(@reader.path(file))
    end
  end
end

# Multiple independently verified checks retain their own immutable exports.
class ExternalValidationOverlays
  attr_reader :registry, :applied_ids
  def initialize(reader, configurations)
    @reader = reader
    grouped = configurations.select { |configuration| configuration['campaign_receipt'] }.group_by { |configuration| configuration.fetch('campaign_receipt') }
    @sweeps = grouped.map do |path, members|
      digests = members.map { |configuration| configuration.fetch('campaign_receipt_sha256') }.uniq
      raise 'Conflicting sweep receipt digests' unless digests.size == 1
      sweep = ValidationSweepReceipt.new(reader, path, digests.first)
      members.each { |configuration| sweep.verify_configuration!(configuration) }
      expected = sweep.case_configurations.values.map { |configuration| configuration.fetch('registry') }.sort
      raise 'Incomplete sweep release configuration' unless members.map { |configuration| configuration.fetch('registry') }.sort == expected
      sweep
    end
    @members = configurations.map { |configuration| ExternalValidationOverlay.new(reader, configuration) }
    @members_by_case = @members.to_h { |member| [member.case_id, member] }
    raise 'Overlapping external-validation case definitions' unless @members_by_case.size == @members.size
    records = {}
    @members.each do |member|
      raise "Overlapping external-validation dispositions" unless (records.keys & member.registry.records.keys).empty?
      records.merge!(member.registry.records)
    end
    @registry = Struct.new(:records).new(records.sort.to_h)
    @applied_ids = @members.flat_map(&:applied_ids).sort
  end
  def excluded?(id) = @applied_ids.include?(id)
  def excluded_ids(campaign) = @members.flat_map { |member| member.excluded_ids(campaign) }.uniq.sort
  def reference_stdout(case_id)
    member = @members_by_case.fetch(case_id) { raise "Unknown supplemental validation case: #{case_id}" }
    member.reference_stdout(case_id)
  end
  def apply!(*arguments)
    @members.each { |member| member.apply!(*arguments) }
    inputs = arguments.last
    @sweeps.each { |sweep| inputs.merge!(sweep.inputs) }
    inputs['tools/validation_sweep_receipt.rb'] = LocalEvalArtifact.sha256(@reader.path('tools/validation_sweep_receipt.rb')) unless @sweeps.empty?
  end
end
