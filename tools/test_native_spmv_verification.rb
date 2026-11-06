# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'current_release'

class NativeSpmvVerificationTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('native-spmv-verification-', '/tmp')
    @release = CurrentRelease.allocate
    @release.instance_variable_set(:@root, @root)
    @id = 'spmv_example_mpi_r1'
    @base = 'batches/20261105-131145'
    @campaign = { 'id' => '20261105-131145', 'source_commit' => 'a' * 40,
      'manifest' => "#{@base}/provenance/evaluation_manifest.yaml" }
    @original = { @id => { 'metadata' => { 'benchmark' => 'spmv',
      'stages' => LocalEvalArtifact::VALIDATION_STAGES.to_h { |stage| [stage, true] } },
      'log_sha256' => { 'validation_out_stdout.log' => 'b' * 64 } } }
    write(@campaign.fetch('manifest'), "manifest\n")
    @files = {}
    add('authorization.json', {})
    add("bindings/#{@id}.json", {})
    add("reviews/#{@id}.json", { 'id' => @id, 'finding' => 'no_work_count_omission_identified',
      'source' => { 'source_commit' => 'a' * 40, 'source_path' => "20261105-131145/#{@id}" },
      'binding_sha256' => @files.fetch("bindings/#{@id}.json") })
    add('native-spmv-inventory.json', { 'validation_manifest_sha256' => digest(@campaign.fetch('manifest')),
      'rows' => [{ 'id' => @id, 'source_commit' => 'a' * 40, 'source_path' => "20261105-131145/#{@id}",
        'validation_stdout_sha256' => 'b' * 64 }] })
    add('completion.json', { 'inventory_sha256' => @files.fetch('native-spmv-inventory.json'),
      'authorization_sha256' => @files.fetch('authorization.json'),
      'review_sha256' => { @id => @files.fetch("reviews/#{@id}.json") } })
    @report = { 'status' => 'complete', 'full_scope_accounted_for' => true, 'evidence_verified' => true,
      'population' => 1, 'new_failures' => [], 'remaining' => 0, 'files_sha256' => @files }
    %w[program_executions compilation benchmark_runs program_changes binaries generated_source_copies complete_disassembly_dumps].each do |key|
      @report[key] = 0
    end
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write(relative, bytes)
    file = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, bytes)
  end

  def digest(relative)
    Digest::SHA256.file(File.join(@root, relative)).hexdigest
  end

  def add(name, data)
    relative = "#{@base}/validation/spmv-work-count/#{name}"
    write(relative, JSON.generate(data))
    @files[name] = digest(relative)
  end

  def verify
    relative = 'validation/spmv-work-count/export.json'
    write("#{@base}/#{relative}", JSON.generate(@report))
    summary = { 'native_spmv_review' => { 'export' => relative, 'export_sha256' => digest("#{@base}/#{relative}"),
      'population' => 1, 'new_failures' => [] } }
    @release.verify_native_spmv!(@campaign, @original, summary)
  end

  def test_complete_source_bound_static_evidence
    verify
    @report['program_executions'] = 1
    assert_match(/scope differs/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_missing_review_coverage_and_changed_sources
    @original['spmv_another_omp_r1'] = @original.fetch(@id)
    assert_raises(RuntimeError) { verify }
    @original.delete('spmv_another_omp_r1')
    @campaign['source_commit'] = 'c' * 40
    assert_match(/identity differs/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_tampered_and_unsafe_evidence
    write("#{@base}/validation/spmv-work-count/bindings/#{@id}.json", 'changed')
    assert_match(/evidence changed/, assert_raises(RuntimeError) { verify }.message)
    @files['../escape.json'] = 'd' * 64
    @files.delete("bindings/#{@id}.json")
    assert_match(/Unsafe/, assert_raises(RuntimeError) { verify }.message)
  end
end
