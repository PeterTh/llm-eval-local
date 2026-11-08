# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require '/home/petert/llm-eval-local/tools/artifact_common'
require_relative 'fable51_generation_evidence'

class Fable51GenerationEvidenceTest < Minitest::Test
  E = Fable51GenerationEvidence
  CAMPAIGN = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium'

  def setup
    @observations = Dir[File.join(CAMPAIGN, 'observations/*.json')].sort.map { |path| JSON.parse(File.read(path)) }
    @completion = JSON.parse(File.read(File.join(CAMPAIGN, 'completion-audit.json')))
    @rows = @observations.to_h do |row|
      [row.fetch('id'), {
        'input_tokens' => row.fetch('inclusive_input_tokens').to_s,
        'output_tokens' => row.fetch('token_counts').fetch('output_tokens').to_s,
        'cached_tokens' => row.fetch('token_counts').fetch('cache_read_input_tokens').to_s,
        'total_tokens' => row.fetch('total_tokens').to_s,
        'api_time' => row.fetch('api_seconds').to_s, 'total_time' => row.fetch('total_seconds').to_s
      }]
    end
  end

  def test_records_and_bound_retry_excerpts
    E.verify_observations!(@observations, @rows, @completion)
    excerpts = E.retry_excerpts!(CAMPAIGN, @completion)
    assert_equal 7, excerpts.size
    assert excerpts.all? { |_, bytes| bytes.include?('429') }
  end

  def test_counter_change_is_rejected
    @rows.values.first['total_tokens'] = '1'
    assert_raises(RuntimeError) { E.verify_observations!(@observations, @rows, @completion) }
  end

  def test_duration_double_subtraction_is_rejected
    @rows.values.first['total_time'] = (@observations.first.fetch('total_seconds') - 120).to_s
    assert_raises(RuntimeError) { E.verify_observations!(@observations, @rows, @completion) }
  end

  def test_unsafe_paths_are_rejected
    ['', '../escape', '/absolute', 'nested/../escape', './relative'].each do |path|
      assert_raises(RuntimeError) { E.safe_relative!(path) }
    end
  end

  def test_all_current_retention_inputs_and_compact_output
    Dir.mktmpdir('fable51-generation-export-test-', '/tmp') do |root|
      batch = File.join(root, 'batches', E::BATCH)
      write = lambda do |relative, bytes|
        E.safe_relative!(relative)
        target = File.join(batch, relative)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, bytes)
      end
      summary = E.retain(campaign: CAMPAIGN, root: root, rows: @rows,
        write: write, copy: ->(source, relative) { write.call(relative, File.binread(source)) },
        json: ->(relative, data) { write.call(relative, JSON.pretty_generate(data) + "\n") },
        jsonl: ->(relative, data) { write.call(relative, data.map { |row| JSON.generate(row) + "\n" }.join) })
      files = Dir[File.join(batch, '**/*')].select { |path| File.file?(path) }
      assert_equal 220, summary.fetch('records')
      assert_equal 7, summary.fetch('provider_failed_attempts')
      assert_operator files.sum { |path| File.size(path) }, :<, 3_000_000
      assert_empty files.select { |path| path.match?(/\.(?:cpp|hpp|o|so|a|sass)$/) }
      assert_empty files.select { |path| File.binread(path, 4) == "\x7fELF" }
      assert_equal 4, Dir[File.join(batch, 'generation/method-layout-*.json')].size
    end
  end
end
