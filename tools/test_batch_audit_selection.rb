# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'current_release'

class BatchAuditSelectionTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('resolved-audit-')
    @base = File.join(@root, 'batches/example')
    FileUtils.mkdir_p(@base)
    @release = CurrentRelease.allocate
    @release.instance_variable_set(:@root, @root)
    @campaign = { 'id' => 'example', 'source_commit' => 'a' * 40 }
    @primary = [decision('mpi-case', 'spmv', 'mpi', 'invalid'), decision('qt-case', 'qtclustering', 'omp', 'invalid')]
    @overlay = [@primary.last.merge('final_verdict' => 'valid', 'timing_fix_required' => false)]
    @original = @primary.to_h do |record|
      [record.fetch('program_id'), { 'id' => record.fetch('program_id'), 'metadata' => {
        'benchmark' => record.fetch('benchmark'), 'par_type' => record.fetch('par_type'),
        'stages' => LocalEvalArtifact::VALIDATION_STAGES.to_h { |stage| [stage, true] } } }]
    end
    @corrections = { 'mpi-case' => { 'original_source' => { 'digest' => 'b' * 64 } } }
    @selection = { 'schema_version' => 1, 'source_commit' => @campaign.fetch('source_commit'),
      'record_count' => 2, 'verdict_counts' => { 'invalid' => 1, 'valid' => 1 }, 'correction_ids' => ['mpi-case'] }
    @summary = { 'timing_audit_selection' => 'selection.json',
      'timing_audit_final_verdicts' => @selection.fetch('verdict_counts').dup,
      'timing_corrections' => { 'audit_selection' => 'selection.json' } }
    write_fixture
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def decision(id, benchmark, backend, verdict)
    { 'program_id' => id, 'benchmark' => benchmark, 'model' => 'model', 'par_type' => backend,
      'run' => 1, 'source_tree_oid' => 'c' * 40, 'source_digest' => 'b' * 64,
      'final_verdict' => verdict, 'final_confidence' => 'high',
      'timing_review_required' => false, 'timing_fix_required' => verdict == 'invalid' }
  end

  def write_fixture
    @selection['ordered_decisions'] = { 'primary.jsonl' => @primary, 'overlay.jsonl' => @overlay }.map do |name, records|
      path = File.join(@base, name)
      File.write(path, records.map { |record| JSON.generate(record) + "\n" }.join)
      { 'path' => name, 'sha256' => LocalEvalArtifact.sha256(path) }
    end
    File.write(File.join(@base, 'selection.json'), JSON.generate(@selection))
    @summary.fetch('timing_corrections')['audit_selection_sha256'] = LocalEvalArtifact.sha256(File.join(@base, 'selection.json'))
  end

  def verify
    @release.verify_batch_audit_selection!(@campaign, @original, @corrections, @summary)
  end

  def test_later_valid_decision_removes_candidate_without_rewriting_primary
    verify
    assert_equal 'invalid', LocalEvalArtifact.read_jsonl(File.join(@base, 'primary.jsonl')).last.fetch('final_verdict')
  end

  def test_rejects_changed_evidence_bytes
    File.open(File.join(@base, 'overlay.jsonl'), 'a') { |file| file.puts('{}') }
    assert_match(/input changed/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_source_change_between_passes
    @overlay.first['source_digest'] = 'd' * 64
    write_fixture
    assert_match(/source differs/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_missing_validated_implementation
    @original['missing'] = @original.fetch('mpi-case').merge('id' => 'missing')
    assert_match(/coverage differs/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_ambiguous_or_misflagged_final_decision
    @overlay.first['timing_review_required'] = true
    write_fixture
    assert_match(/unresolved audit/, assert_raises(RuntimeError) { verify }.message)
    @overlay.first['timing_review_required'] = false
    @overlay.first['timing_fix_required'] = true
    write_fixture
    assert_match(/unresolved audit/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_wrong_correction_source_and_selection_binding
    @corrections.fetch('mpi-case').fetch('original_source')['digest'] = 'd' * 64
    assert_match(/correction source differs/, assert_raises(RuntimeError) { verify }.message)
    @corrections.fetch('mpi-case').fetch('original_source')['digest'] = 'b' * 64
    @summary.fetch('timing_corrections')['audit_selection_sha256'] = '0' * 64
    assert_match(/binding differs/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_unsafe_selection_path
    @summary['timing_audit_selection'] = '../outside.json'
    assert_match(/unsafe release path/, assert_raises(RuntimeError) { verify }.message)
  end
end
