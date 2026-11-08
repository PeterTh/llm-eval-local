# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'audit-citation-normalization'
class CitationNormalizationTest < Minitest::Test
  def source(lines)
    { 'verdict' => 'invalid', 'confidence' => 'high', 'evidence' => [{ 'path' => 'a.cpp', 'lines' => lines, 'finding' => 'Unchanged claim.' }] }
  end
  def test_split_preserves_meaning_and_original
    original = source('1218-1220, 1282-1285')
    result, edits = AuditCitationNormalization.normalize(original)
    assert_equal %w[1218-1220 1282-1285], result['evidence'].map { |e| e['lines'] }
    assert_equal ['Unchanged claim.'] * 2, result['evidence'].map { |e| e['finding'] }
    assert_equal 'invalid', result['verdict']
    assert_equal '1218-1220, 1282-1285', original['evidence'].first['lines']
    assert_equal 1, edits.size
  end
  def test_semicolon_and_single_line
    result, = AuditCitationNormalization.normalize(source('9; 15-18'))
    assert_equal %w[9 15-18], result['evidence'].map { |e| e['lines'] }
  end
  def test_rejects_inference_or_bad_syntax
    ['10 through 20', '10-', '10, maybe 20', '10-20; ', '10-20-30', '10–20'].each do |value|
      assert_raises(RuntimeError) { AuditCitationNormalization.normalize(source(value)) }
    end
  end
  def test_no_op_rejected
    assert_raises(RuntimeError) { AuditCitationNormalization.normalize(source('10-20')) }
  end
end
