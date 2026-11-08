# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'export_timing_revision_evidence'

class TimingRevisionEvidenceTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('timing-revision-test-', '/tmp')
    @gate_path = File.join(@root, 'correction-revision-1.json')
    @gate = { 'passed' => true, 'prior_evidence_unchanged' => true, 'program_id' => 'changed',
      'accepted_corrections' => 2, 'unchanged_proposals' => 1 }
    %w[prior_roots evidence_roots].each do |epoch|
      @gate[epoch] = %w[proposals review adjudication].to_h do |stage|
        directory = File.join(@root, epoch, stage)
        ids = stage == 'adjudication' ? ['same'] : %w[changed same]
        write(File.join(directory, 'inventory.jsonl'), ids.map { |id| JSON.generate({ 'id' => id }) + "\n" }.join)
        ids.each do |id|
          payload = { 'program_id' => id, 'value' => (id == 'same' && stage != 'adjudication' ? 'same' : epoch) }
          write(File.join(directory, stage == 'proposals' ? stage : 'results', "#{id}.json"), JSON.pretty_generate(payload) + "\n")
        end
        write(File.join(directory, 'manifest.yaml'), "---\nfixture: true\n")
        [stage, directory]
      end
    end
    write(File.join(@gate['prior_roots']['proposals'], 'materialized/summary-full.yaml'), "---\ncompile_successes: 2\n")
    write(File.join(@gate['evidence_roots']['review'], 'reused-reviews.json'), "{}\n")
    %w[correction-revision-feedback.json correction-revision-launch.json correction-revision-driver.rb
      reuse-unchanged-correction-reviews.rb launch-correction-revision.rb correction-full-operator-scope-review.json
      record-full-patch-scope-review.rb cahn-hilliard-event-semantics-check.json
      correction-revision-diff-check.json verify-correction-revision-scope.rb
      correction-followup-rebinding.json prepare-revised-correction-followup.rb].each { |name| write(File.join(@root, name), "{}\n") }
    { 'prior_proposal_sha256' => %w[prior_roots proposals proposals changed.json],
      'prior_independent_review_sha256' => %w[prior_roots review results changed.json],
      'revised_proposal_sha256' => %w[evidence_roots proposals proposals changed.json],
      'accepted_review_sha256' => %w[evidence_roots review results changed.json],
      'reuse_receipt_sha256' => %w[evidence_roots review reused-reviews.json] }.each do |key, (epoch, stage, *tail)|
      @gate[key] = LocalEvalArtifact.sha256(File.join(@gate[epoch][stage], *tail))
    end
    @gate['operator_scope_review_sha256'] = LocalEvalArtifact.sha256(File.join(@root, 'correction-full-operator-scope-review.json'))
    save_gate
  end

  def teardown
    FileUtils.remove_entry_secure(@root)
  end

  def write(path, bytes)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
  end

  def save_gate
    write(@gate_path, JSON.pretty_generate(@gate) + "\n")
  end

  def test_only_changed_results_are_retained_and_overwrite_is_rejected
    files = TimingRevisionEvidenceExport.collect(@gate_path)
    assert files.key?('proposals/superseded/changed.json')
    refute files.key?('proposals/superseded/same.json')
    assert files.key?('adjudication/superseded/same.json')
    batch = File.join(@root, 'batch')
    report = TimingRevisionEvidenceExport.run(batch_dir: batch, gate_path: @gate_path)
    assert_equal files.size, report.fetch('files')
    assert_equal files.values.sum(&:bytesize), report.fetch('bytes')
    assert_raises(RuntimeError) { TimingRevisionEvidenceExport.run(batch_dir: batch, gate_path: @gate_path) }
  end

  def test_rejects_unrelated_proposal_change
    write(File.join(@gate['evidence_roots']['proposals'], 'proposals/same.json'), "{}\n")
    assert_raises(RuntimeError) { TimingRevisionEvidenceExport.collect(@gate_path) }
  end

  def test_rejects_changed_revision_binding
    @gate['revised_proposal_sha256'] = '0' * 64
    save_gate
    assert_raises(RuntimeError) { TimingRevisionEvidenceExport.collect(@gate_path) }
  end

  def test_rejects_unaccepted_gate_and_unsafe_id
    @gate['passed'] = false
    save_gate
    assert_raises(RuntimeError) { TimingRevisionEvidenceExport.collect(@gate_path) }
    @gate['passed'] = true
    @gate['program_id'] = '../escape'
    save_gate
    assert_raises(RuntimeError) { TimingRevisionEvidenceExport.collect(@gate_path) }
  end

  def test_rejects_changed_operator_scope_receipt
    write(File.join(@root, 'correction-full-operator-scope-review.json'), "changed\n")
    assert_raises(RuntimeError) { TimingRevisionEvidenceExport.collect(@gate_path) }
  end
end
