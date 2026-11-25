# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'export_native_spmv'

class NativeSpmvExportTest < Minitest::Test
  def setup
    @report = { 'status' => 'complete', 'full_scope_accounted_for' => true, 'evidence_verified' => true,
      'population' => 20, 'reused_pilot_reviews' => 0, 'new_reviews' => 20, 'remaining' => 0,
      'review_sha256' => { 'spmv_example_mpi_r1' => 'a' * 64 }, 'new_failures' => [],
      'program_executions' => 0, 'compilation' => 0, 'benchmark_runs' => 0, 'program_changes' => 0 }
  end

  def test_only_verified_complete_static_evidence_can_be_exported
    NativeSpmvExport.verify_completion!(@report, @report)
    %w[remaining program_executions compilation benchmark_runs program_changes].each do |key|
      assert_raises(RuntimeError) { NativeSpmvExport.verify_completion!(@report.merge(key => 1), @report) }
    end
    assert_raises(RuntimeError) { NativeSpmvExport.verify_completion!(@report, @report.merge('new_reviews' => 19)) }
    assert_raises(RuntimeError) { NativeSpmvExport.verify_completion!(@report, @report.merge('review_sha256' => {})) }
    assert_raises(RuntimeError) { NativeSpmvExport.verify_completion!(@report.merge('new_failures' => ['unresolved']), @report) }
  end

  def test_explicit_quality_evidence_is_json_only_and_cannot_replace_native_records
    Dir.mktmpdir('native-spmv-export-test-') do |directory|
      path = File.join(directory, 'quality.json')
      File.write(path, JSON.generate('passed' => true))
      sources = { 'completion.json' => 'native-completion' }
      name = 'quality-evidence/pilot/quality-gate.json'
      NativeSpmvExport.add_supplemental_sources!(sources, name => path)
      assert_equal path, sources.fetch(name)
      assert_equal 'native-completion', sources.fetch('completion.json')
      assert_raises(RuntimeError) { NativeSpmvExport.add_supplemental_sources!(sources, name => path) }
      %w[completion.json ../quality.json quality-evidence/../quality.json quality-evidence/code.rb].each do |unsafe|
        assert_raises(RuntimeError) { NativeSpmvExport.add_supplemental_sources!({}, unsafe => path) }
      end
      link = File.join(directory, 'link.json')
      File.symlink(path, link)
      assert_raises(RuntimeError) { NativeSpmvExport.add_supplemental_sources!({}, name => link) }
      File.write(path, 'not JSON')
      assert_raises(JSON::ParserError) { NativeSpmvExport.add_supplemental_sources!({}, name => path) }
    end
  end
end
