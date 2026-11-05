# frozen_string_literal: true
require 'open3'
require 'rbconfig'
require_relative 'artifact_common'

# Verify the complete retained sweep before exposing its small eligibility view.
# The bundled verifier imports only JSON/numerical replay code, never the local
# execution stack, and replays complete failure arrays without generated runs.
class FullArraySweepReceipt
  include LocalEvalArtifact
  attr_reader :inputs, :case_configurations

  def initialize(reader, relative, expected_digest)
    @reader, @relative, @root = reader, relative, File.dirname(relative)
    receipt_path = reader.path(relative)
    raise 'Full-array sweep receipt digest differs' unless sha256(receipt_path) == expected_digest
    receipt = JSON.parse(File.read(receipt_path))
    unless receipt.fetch('schema_version') == 1 && receipt.fetch('kind') == 'full-array-correctness-sweep'
      raise 'Unsupported full-array sweep receipt'
    end
    @inputs = { relative => expected_digest }
    pin_members(@root, receipt)
    entry = 'verification-method/tools/validation_audit/verify_full_array_full_export.rb'
    raise 'Missing standalone full-array verifier' unless receipt.fetch('files_sha256').key?(entry)
    # The frozen verifier has its own comparison-policy snapshot. Keep its
    # constants and top-level validator out of the current release process.
    code = 'puts JSON.generate(ValidationAudit::FullArrayFullVerification.run(ARGV.fetch(0), quiet: true))'
    output, error, status = Open3.capture3(RbConfig.ruby, '-r', reader.path(File.join(@root, entry)),
      '-e', code, reader.path(@root))
    raise "Full-array offline verification failed: #{error}" unless status.success?
    result = JSON.parse(output)
    unless result.fetch('verified_records') == receipt.fetch('population') &&
        result.fetch('verified_failure_ids') == receipt.fetch('failed_ids')
      raise 'Full-array offline verification scope differs'
    end
    pilot_name = receipt.fetch('shared_pilot').fetch('directory')
    raise 'Unsafe full-array shared pilot' unless pilot_name.match?(/\A[a-zA-Z0-9_-]+\z/)
    pilot = File.join(File.dirname(@root), pilot_name)
    pilot_receipt = File.join(pilot, 'export.json')
    @inputs[pilot_receipt] = receipt.fetch('shared_pilot').fetch('export_sha256')
    raise 'Shared full-array pilot changed' unless sha256(reader.path(pilot_receipt)) == @inputs.fetch(pilot_receipt)
    pin_members(pilot, JSON.parse(File.read(reader.path(pilot_receipt))))
    @case_configurations = receipt.fetch('eligibility').to_h do |benchmark, summary|
      directory = File.join(@root, 'eligibility', benchmark)
      data = JSON.parse(File.read(reader.path(File.join(directory, 'exclusions.json'))))
      configuration = { 'registry' => File.join(directory, 'exclusions.json'),
        'records' => File.join(directory, 'records.jsonl'), 'registry_sha256' => summary.fetch('registry_sha256'),
        'export_sha256' => sha256(reader.path(File.join(directory, 'export.json'))),
        'applied_ids' => data.fetch('records').map { |row| row.fetch('id') },
        'campaign_receipt' => relative, 'campaign_receipt_sha256' => expected_digest }
      [benchmark, configuration]
    end
  end

  def verify_configuration!(configuration)
    benchmark = File.basename(File.dirname(configuration.fetch('registry')))
    raise 'Release configuration differs from verified full-array sweep' unless configuration == @case_configurations.fetch(benchmark)
  end

  def registry(configuration)
    verify_configuration!(configuration)
    path = @reader.path(configuration.fetch('registry'))
    raise 'Full-array registry changed after verification' unless sha256(path) == configuration.fetch('registry_sha256')
    [path, JSON.parse(File.read(path))]
  end

  private

  def pin_members(root, receipt)
    members = receipt.fetch('files_sha256')
    members.each do |name, digest|
      unless name.is_a?(String) && !name.start_with?('/') && name.split('/').none? { |part| ['', '.', '..'].include?(part) }
        raise 'Unsafe full-array evidence path'
      end
      relative = File.join(root, name)
      raise "Full-array evidence changed: #{relative}" unless sha256(@reader.path(relative)) == digest
      @inputs[relative] = digest
    end
    actual = regular_files(@reader.path(root)).map { |path| relative_path(@reader.path('.'), path) }.sort
    expected = (members.keys.map { |name| File.join(root, name) } + [File.join(root, 'export.json')]).sort
    raise 'Unpinned full-array evidence files' unless actual == expected
    raise 'Full-array retention size differs' unless members.keys.sum { |name| File.size(@reader.path(File.join(root, name))) } == receipt.fetch('retained_bytes')
  end
end

# This registry cannot be used without complete-sweep numerical verification.
class FullArrayValidationRegistry
  attr_reader :path, :digest, :data, :records
  def initialize(configuration, sweep)
    raise 'Full-array registry requires a verified complete sweep' unless sweep.is_a?(FullArraySweepReceipt)
    @path, @data = sweep.registry(configuration)
    @digest = LocalEvalArtifact.sha256(@path)
    @records = @data.fetch('records').to_h { |record| [record.fetch('id'), record] }
  end
  def reason(id)
    "Output comparison FAILED (#{@data.fetch('case').fetch('id')}): #{@records.fetch(id).fetch('result').fetch('comparison').last}"
  end
end
