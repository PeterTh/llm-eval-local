# frozen_string_literal: true
require 'minitest/autorun'
require 'tempfile'
require_relative 'codex_usage_records'

class CodexUsageRecordsTest < Minitest::Test
  def with_records(rows)
    Tempfile.create(['usage-loader-', '.jsonl'], '/tmp') do |file|
      rows.each { |row| file.puts(JSON.generate(row)) }
      file.flush
      yield file.path
    end
  end

  def test_legacy_evidence_still_uses_the_immutable_parser
    path = File.expand_path('../metadata/codex-usage/20261102-030935.jsonl', __dir__)
    legacy = JSON.parse(File.open(path, &:readline))
    with_records([legacy]) do |file|
      assert_equal CodexUsage.load_records(file), CodexUsageRecords.load_records(file)
    end
    with_records([legacy, legacy]) { |file| assert_raises(CodexUsage::Invalid) { CodexUsageRecords.load_records(file) } }
    with_records([legacy.merge('schema_version' => 999)]) { |file| assert_raises(CodexUsage::Invalid) { CodexUsageRecords.load_records(file) } }
    with_records([]) { |file| assert_raises(CodexUsage::Invalid) { CodexUsageRecords.load_records(file) } }
  end

  def test_native_schema_dispatch_is_explicit_and_does_not_modify_legacy_parser
    native = { 'schema_version' => 2, 'run_id' => 'example' }
    calls = []
    CodexTreeUsage.stub(:validate_record!, ->(record) { calls << record; record }) do
      with_records([native]) { |file| assert_equal({ 'example' => native }, CodexUsageRecords.load_records(file)) }
    end
    assert_equal [native], calls
    assert_raises(CodexUsage::Invalid) { CodexUsage.validate_record!(native) }
    with_records([native]) { |file| assert_raises(StandardError) { CodexUsageRecords.load_records(file) } }
  end
end
