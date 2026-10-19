# frozen_string_literal: true
require "minitest/autorun"
require_relative "export_opencode_supplement"

class OpenCodeSupplementTest < Minitest::Test
  def record(id, benchmark, backend, valid: true)
    stages = LocalEvalArtifact::VALIDATION_STAGES.to_h { |stage| [stage, true] }
    stages["output_comparison"] = valid
    { "id" => id, "metadata" => { "benchmark" => benchmark, "par_type" => backend, "stages" => stages } }
  end

  def test_campaign_pins_are_distinct_and_default_is_backwards_compatible
    original = OpenCodeSupplement.configuration(OpenCodeSupplement::DEFAULT_BATCH)
    luna = OpenCodeSupplement.configuration("20261018-224015")
    assert_equal "352c09d57e14ef93744aa8cc741ff52884079e5f", original.fetch("original")
    assert_equal "fd64978a13b9a4f3ac6a5e368972316d0c159aa1", luna.fetch("original")
    assert_equal "20261019-luna6-opencode", luna.fetch("audit_id")
    assert_equal "luna6-opencode-medium", luna.fetch("suffix")
    assert_raises(RuntimeError) { OpenCodeSupplement.configuration("../unknown") }
  end

  def test_audit_scope_is_valid_mpi_hybrid_and_all_backend_qt_without_duplicates
    records = [record("a", "nbody", "mpi"), record("b", "nbody", "hybrid"),
      record("c", "qtclustering", "omp"), record("d", "qtclustering", "mpi"),
      record("e", "qtclustering", "cuda"), record("f", "nbody", "omp"),
      record("g", "nbody", "mpi", valid: false), record("h", "qtclustering", "cuda", valid: false)]
    assert_equal %w[a b c d e], OpenCodeSupplement.audit_scope(records.reverse)
  end
end
