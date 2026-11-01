# frozen_string_literal: true

require "minitest/autorun"
require_relative "full_check"

class TestBoundaryCheck < Minitest::Test
  B = UnstructuredBoundaryCheck
  F = UnstructuredBoundaryFullCheck

  def setup
    @rows = F.records.to_h { |row| [row.fetch("id"), row] }
    @reference = B.read_json(File.join(B::EVIDENCE, "reference.json"))
    @reference_result, @reference_output = F.verify_result(@reference)
  end

  def test_frozen_inventory_and_scope
    manifest = B.check_inputs
    assert_equal 287, @rows.size
    assert_equal 277, @rows.values.count { |row| row.fetch("origin") == "published_successful_measurement" }
    assert_equal 10, @rows.values.count { |row| row.fetch("origin") == "beam_validation_pass" }
    assert_equal 252, manifest.fetch("cached_builds_verified")
    assert_equal 35, manifest.fetch("rebuild_required_ids").size
    assert @rows.values.all? { |row| %w[mpi hybrid].include?(row.fetch("backend")) }
  end

  def test_pilot_rejects_numeric_error_not_hash
    result, output = F.verify_result(@rows.fetch(B::KNOWN_BAD))
    refute result.fetch("passed")
    assert result.fetch("execution").fetch("success")
    assert result.fetch("internal_validation")
    refute result.fetch("comparison").first
    assert_match(/Numeric value mismatch/, result.fetch("comparison").last)
    assert_equal result.fetch("comparison"), validate(@reference_output, output, "unstructured")
  end

  def test_controls_match_and_hash_is_informational
    assert @reference_result.fetch("passed")
    B::CONTROLS.each do |id|
      result, output = F.verify_result(@rows.fetch(id))
      assert result.fetch("passed")
      assert validate(@reference_output, output, "unstructured").first
      assert validate(@reference_output, output.gsub(/^Hash: .*$/, "Hash: deliberately-different"), "unstructured").first
    end
  end

  def test_reuse_rejects_wrong_source_and_binary
    row = @rows.fetch(B::CONTROLS.first)
    assert_raises(RuntimeError) { F.verify_result(row.merge("source_commit" => "0" * 40)) }
    assert_raises(RuntimeError) { F.verify_result(row.merge("cache" => row.fetch("cache").merge("executable_sha256" => "0" * 64))) }
  end

  def test_every_rebuild_has_exact_regular_git_sources
    @rows.values.reject { |row| row["cache"] }.each do |row|
      expected = row.fetch("staged_source_git_blob_ids")
      assert_equal expected, B.source_files(B::SOURCE, row.fetch("source_commit"), row.fetch("source_path"))
      assert expected.key?("unstructured/CMakeLists.txt")
      assert expected.keys.any? { |path| path.match?(%r{\Aunstructured/unstructured\.(?:cpp|cu)\z}) }
      assert expected.keys.none? { |path| path.start_with?('/') || path.split('/').include?('..') }
    end
  end
end
