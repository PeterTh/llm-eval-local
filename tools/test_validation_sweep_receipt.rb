# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'validation_sweep_receipt'
require_relative 'external_validation_overlay'

class ValidationSweepReceiptTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  Reader = Struct.new(:root) do
    def path(relative) = File.join(root, relative)
  end

  def write(path, data)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(data) + "\n")
  end

  def fixture(directory)
    pilot = File.join(ROOT, 'validation-supplements/20261103-shape-topology-pilot')
    all = File.readlines(File.join(pilot, 'records.jsonl')).map { |line| JSON.parse(line) }
    rows = all.select { |r| !r.fetch('superseded_case') && r.dig('source', 'benchmark') == 'nbody' && r.dig('source', 'backend') == 'cuda' }.sort_by { |r| r.fetch('id') }
    raise 'Fixture requires one pass and one failure' unless rows.size == 2 && rows.count { |r| r.dig('result', 'passed') } == 1
    rows = rows.map do |record|
      record.reject { |key, _| key == 'superseded_case' }.merge('log_sha256' => record.fetch('logs').transform_values { |bytes| Digest::SHA256.hexdigest(bytes) })
    end
    definition = rows.first.fetch('result').fetch('definition')
    label = definition.fetch('id')
    base = File.join(directory, 'sweep')
    case_dir = File.join(base, label)
    FileUtils.mkdir_p(case_dir)
    File.write(File.join(case_dir, 'records.jsonl'), rows.map { |row| JSON.generate(row) + "\n" }.join)
    reference = JSON.parse(File.read(File.join(pilot, 'references.json'))).fetch(label)
    reference['source_commit'] = reference.fetch('result').fetch('source_commit')
    write(File.join(case_dir, 'reference.json'), reference)
    original_bindings = JSON.parse(File.read(File.join(pilot, 'build-bindings.json')))
    bindings = rows.map do |row|
      original_bindings.fetch(row.fetch('id')).reject { |key, _| key == 'source_files' }.merge(
        'source_files_sha256' => Digest::SHA256.hexdigest(JSON.generate(row.fetch('source').fetch('source_files'))))
    end
    write(File.join(case_dir, 'build-bindings.json'), bindings)
    exclusions = rows.reject { |r| r.dig('result', 'passed') }.map do |row|
      row.fetch('source').slice('id', 'source_commit', 'source_path', 'validation_record').merge(
        'stages' => SupplementalValidationRegistry::STAGES, 'case_id' => label,
        'result' => row.fetch('result'), 'result_sha256' => row.fetch('result_sha256'), 'stdout' => row.fetch('logs').fetch('stdout'))
    end
    write(File.join(case_dir, 'exclusions.json'), { 'schema_version' => 2, 'case' => definition, 'record_count' => 1,
      'failed_stage' => 'output_comparison', 'authorization' => { 'source' => 'user', 'statement' => 'Unit-test fixture, not a real campaign authorization.' },
      'reference' => reference.slice('stdout', 'stdout_sha256'), 'records' => exclusions })
    full_plan = { 'scope' => 'Two-record test fixture', 'groups' => [{ 'definition' => definition, 'backend' => 'cuda', 'rows' => rows.map { |r| r.fetch('source') } }],
      'checks' => 2, 'unique_programs' => 2 }
    plan_digest = Digest::SHA256.hexdigest(JSON.pretty_generate(full_plan) + "\n")
    compact = full_plan.merge('groups' => full_plan.fetch('groups').map { |g| g.to_h { |k, v| k == 'rows' ? ['row_ids', v.map { |r| r.fetch('id') }] : [k, v] } })
    write(File.join(base, 'plan.json'), compact)
    write(File.join(base, 'shape-topology-full-authorization.json'), { 'source' => 'user', 'approved' => true,
      'scope' => 'full-shape-topology-sweep', 'planned_checks' => 2, 'plan_sha256' => plan_digest, 'benchmark_runs' => 0 })
    failed = exclusions.map { |r| r.fetch('id') }
    write(File.join(base, 'shape-topology-full-completion.json'), { 'status' => 'complete', 'plan_sha256' => plan_digest,
      'accounted_checks' => 2, 'completed_checks' => 2, 'passed_checks' => 1, 'skipped_checks' => 0, 'failed_ids' => failed, 'benchmark_runs' => 0 })
    repin(base, label, definition, failed)
    [Reader.new(directory), label, definition, failed]
  end

  def repin(base, label, definition, failed)
    case_dir = File.join(base, label)
    paths = Dir[File.join(case_dir, '*')].reject { |path| File.basename(path) == 'export.json' }
    summary = { 'schema_version' => 1, 'case' => definition, 'records' => 2, 'executed' => 2, 'skipped' => 0, 'failed' => 1,
      'registry_sha256' => LocalEvalArtifact.sha256(File.join(case_dir, 'exclusions.json')),
      'files_sha256' => paths.sort.to_h { |path| [File.basename(path), LocalEvalArtifact.sha256(path)] },
      'retained_bytes' => paths.sum { |path| File.size(path) }, 'benchmark_runs' => 0 }
    write(File.join(case_dir, 'export.json'), summary)
    files = LocalEvalArtifact.regular_files(base).reject { |path| path == File.join(base, 'export.json') }
    write(File.join(base, 'export.json'), { 'schema_version' => 1, 'cases' => { label => summary }, 'planned_checks' => 2,
      'executed_checks' => 2, 'skipped_checks' => 0, 'failed_ids' => failed, 'benchmark_runs' => 0,
      'files_sha256' => files.to_h { |path| [path.delete_prefix(base + '/'), LocalEvalArtifact.sha256(path)] },
      'retained_bytes' => files.sum { |path| File.size(path) } })
  end

  def verify(reader)
    ValidationSweepReceipt.new(reader, 'sweep/export.json', LocalEvalArtifact.sha256(reader.path('sweep/export.json')))
  end

  def test_reconstructs_scope_and_reproduces_pass_and_failure_without_running_programs
    Dir.mktmpdir('validation-sweep-test-', '/tmp') do |directory|
      reader, label, _definition, failed = fixture(directory)
      sweep = verify(reader)
      configuration = sweep.case_configurations.fetch(label)
      assert_equal failed, configuration.fetch('applied_ids')
      sweep.verify_configuration!(configuration)
      assert sweep.inputs.key?('sweep/shape-topology-full-authorization.json')
      assert sweep.inputs.key?('sweep/shape-topology-full-completion.json')
      assert sweep.inputs.key?("sweep/#{label}/records.jsonl")
      assert_raises(RuntimeError) { sweep.verify_configuration!(configuration.merge('applied_ids' => [])) }
      overlays = ExternalValidationOverlays.new(reader, [configuration])
      assert_equal failed, overlays.applied_ids
      assert_equal failed, overlays.registry.records.keys
    end
  end

  def test_rejects_changed_files_and_unpinned_extras
    Dir.mktmpdir('validation-sweep-test-', '/tmp') do |directory|
      reader, = fixture(directory)
      path = reader.path('sweep/plan.json')
      original = File.read(path)
      File.write(path, original + ' ')
      assert_match(/evidence changed/, assert_raises(RuntimeError) { verify(reader) }.message)
      File.write(path, original)
      File.write(reader.path('sweep/unpinned.txt'), 'fixture')
      assert_match(/Unpinned/, assert_raises(RuntimeError) { verify(reader) }.message)
    end
  end

  def test_rejects_changed_approval_even_when_receipts_are_recomputed
    Dir.mktmpdir('validation-sweep-test-', '/tmp') do |directory|
      reader, label, definition, failed = fixture(directory)
      path = reader.path('sweep/shape-topology-full-authorization.json')
      approval = JSON.parse(File.read(path)).merge('plan_sha256' => '0' * 64)
      write(path, approval)
      repin(reader.path('sweep'), label, definition, failed)
      assert_match(/plan does not reconstruct/, assert_raises(RuntimeError) { verify(reader) }.message)
    end
  end

  def test_rejects_false_verdict_even_when_receipts_are_recomputed
    Dir.mktmpdir('validation-sweep-test-', '/tmp') do |directory|
      reader, label, definition, failed = fixture(directory)
      path = reader.path("sweep/#{label}/records.jsonl")
      rows = File.readlines(path).map { |line| JSON.parse(line) }
      changed = rows.find { |row| row.dig('result', 'passed') }
      changed.fetch('result')['comparison'] = [true, 'A fabricated verdict description']
      changed['result_sha256'] = Digest::SHA256.hexdigest(JSON.pretty_generate(changed.fetch('result')) + "\n")
      File.write(path, rows.map { |row| JSON.generate(row) + "\n" }.join)
      repin(reader.path('sweep'), label, definition, failed)
      assert_match(/verdict does not reproduce/, assert_raises(RuntimeError) { verify(reader) }.message)
    end
  end
end
