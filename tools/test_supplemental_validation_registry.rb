# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative 'current_release'

class SupplementalValidationRegistryTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  DIRECTORY = 'validation-supplements/20261103-floyd-integer-hash'

  def setup
    @path = File.join(ROOT, DIRECTORY, 'exclusions.json')
    @data = JSON.parse(File.read(@path))
  end

  def with_registry(data)
    Dir.mktmpdir('supplemental-registry-test-', '/tmp') do |directory|
      path = File.join(directory, 'exclusions.json')
      File.write(path, JSON.pretty_generate(data) + "\n")
      yield path
    end
  end

  def test_reproduces_all_floyd_failures_without_executing_programs
    registry = SupplementalValidationRegistry.new(@path)
    assert_equal 3, registry.records.size
    assert_equal 2, registry.records.values.count { |r| r.fetch('result').key?('archived_validation') }
    registry.records.each_key { |id| assert_match(/Output comparison FAILED/, registry.reason(id)) }
  end

  def test_rejects_changed_definition_output_result_or_stage
    mutations = [
      ->(data) { data.fetch('case').fetch('args')[-1] = '513' },
      ->(data) { data.fetch('records').first['stdout'] += 'changed' },
      ->(data) { data.fetch('records').first.fetch('result')['checked_at'] = 'changed' },
      ->(data) { data.fetch('records').first.fetch('stages')['validation_run'] = false },
      ->(data) { data.fetch('records').first['source_commit'] = '0' * 40 }
    ]
    mutations.each do |mutate|
      data = Marshal.load(Marshal.dump(@data))
      mutate.call(data)
      with_registry(data) { |path| assert_raises(RuntimeError) { SupplementalValidationRegistry.new(path) } }
    end
  end

  def floyd_configuration
    export = JSON.parse(File.read(File.join(ROOT, DIRECTORY, 'export.json')))
    { 'registry' => "#{DIRECTORY}/exclusions.json", 'records' => "#{DIRECTORY}/records.jsonl",
      'registry_sha256' => export.fetch('registry_sha256'),
      'export_sha256' => LocalEvalArtifact.sha256(File.join(ROOT, DIRECTORY, 'export.json')),
      'applied_ids' => @data.fetch('records').map { |row| row.fetch('id') } }
  end

  def test_composes_independent_overlays_preserving_archived_measurements
    reader = CurrentRelease.new(ROOT)
    old = JSON.parse(File.read(File.join(ROOT, 'release/catalog.json'))).fetch('external_validation')
    configurations = old.is_a?(Array) ? old : [old]
    configurations = configurations.reject { |c| c.fetch('registry').start_with?(DIRECTORY + '/') } + [floyd_configuration]
    overlay = ExternalValidationOverlays.new(reader, configurations)
    rows = overlay.applied_ids.map do |id|
      record = overlay.registry.records.fetch(id)
      benchmark, model, backend, repetition = id.split('_')
      { 'benchmark' => benchmark, 'model' => model, 'par_type' => backend, 'run' => repetition.delete_prefix('r'),
        'source_path' => record.fetch('source_path'), 'validation_status' => '5',
        'benchmark_success' => 'true', 'benchmark_times' => '1;2;3', 'benchmark_median_time' => '2',
        'timing_fixed' => 'true', 'original_source_commit' => 'unchanged-original' }
    end
    archive = overlay.applied_ids.to_h { |id| [id, { 'success' => true, 'times' => [1, 2, 3] }] }
    archive_digest = Digest::SHA256.hexdigest(JSON.generate(archive))
    effective = Marshal.load(Marshal.dump(archive))
    sources = overlay.registry.records.transform_values { |record| record.fetch('source_commit') }
    inputs = {}
    overlay.apply!(rows, effective, sources, rows.first.keys, inputs)
    assert_empty effective
    assert_equal archive_digest, Digest::SHA256.hexdigest(JSON.generate(archive))
    rows.each do |row|
      assert_equal '4', row.fetch('validation_status')
      assert_nil row.fetch('benchmark_times')
      assert_equal 'true', row.fetch('timing_fixed')
      assert_equal 'unchanged-original', row.fetch('original_source_commit')
    end
    assert inputs.key?("#{DIRECTORY}/records.jsonl")
  end

  def test_rejects_duplicate_dispositions
    reader = CurrentRelease.new(ROOT)
    assert_match(/Overlapping/, assert_raises(RuntimeError) {
      ExternalValidationOverlays.new(reader, [floyd_configuration, floyd_configuration])
    }.message)
  end

  def test_revalidation_selects_the_named_case_reference_in_both_catalog_formats
    reader = CurrentRelease.new(ROOT)
    catalog = JSON.parse(File.read(File.join(ROOT, 'release/catalog.json')))
    configurations = catalog.fetch('external_validation')
    configurations = [configurations] unless configurations.is_a?(Array)
    legacy = configurations.find { |c| c.fetch('registry').include?('20261101-unstructured-boundary/') }
    single = ExternalValidationOverlay.new(reader, legacy)
    multiple = ExternalValidationOverlays.new(reader, [floyd_configuration, legacy])
    boundary = ExternalValidationExclusions::CASE_ID
    assert_equal single.reference_stdout(boundary), multiple.reference_stdout(boundary)
    assert_equal @data.fetch('reference').fetch('stdout'), multiple.reference_stdout('floyd-integer-hash-v1')
    refute_equal multiple.reference_stdout(boundary), multiple.reference_stdout('floyd-integer-hash-v1')
    [single, multiple].each do |overlay|
      assert_match(/Unknown supplemental validation case/, assert_raises(RuntimeError) { overlay.reference_stdout('missing-case') }.message)
    end
  end

  def test_reproduces_the_two_shape_pilot_failures_without_new_executions
    base = File.join(ROOT, 'validation-supplements/20261103-shape-topology-pilot')
    references = JSON.parse(File.read(File.join(base, 'references.json')))
    failures = File.readlines(File.join(base, 'records.jsonl')).map { |line| JSON.parse(line) }
      .select { |record| !record.fetch('superseded_case') && !record.dig('result', 'passed') }
    assert_equal 2, failures.size
    failures.each do |record|
      result = record.fetch('result')
      definition = result.fetch('definition')
      reference = references.fetch(definition.fetch('id'))
      exclusion = record.fetch('source').slice('id', 'source_commit', 'source_path', 'validation_record').merge(
        'stages' => SupplementalValidationRegistry::STAGES, 'case_id' => definition.fetch('id'),
        'result' => result, 'result_sha256' => record.fetch('result_sha256'), 'stdout' => record.fetch('logs').fetch('stdout'))
      data = { 'schema_version' => 2, 'case' => definition, 'record_count' => 1, 'failed_stage' => 'output_comparison',
        'authorization' => { 'source' => 'user', 'statement' => 'Retain supplemental failures as external validation failures.' },
        'reference' => reference.slice('stdout', 'stdout_sha256'), 'records' => [exclusion] }
      with_registry(data) do |path|
        registry = SupplementalValidationRegistry.new(path)
        assert_equal [record.fetch('id')], registry.records.keys
        assert_includes registry.reason(record.fetch('id')), 'Numeric value mismatch'
      end
    end
  end
end
