# frozen_string_literal: true
require "minitest/autorun"
require_relative "current_release"

class ObservationReplacementsTest < Minitest::Test
  def setup
    @rows = [1, 2, 3].map { |i| { "benchmark" => "test", "model" => "model", "par_type" => "mpi", "run" => i.to_s, "value" => "old" } }
    @ids = @rows.map { |r| CurrentRelease.id(r) }
    @validations = @ids.to_h { |id| [id, { "passed" => true }] }
    @records = @ids.to_h { |id| [id, { "time" => 10.0 }] }
    selected = @ids.take(2)
    before = { "rows" => @rows.to_h { |r| [CurrentRelease.id(r), r] }, "validations" => @validations, "benchmarks" => @records }
    guard = { "prior_sha256" => ObservationReplacements.digest(before), "unaffected_observations" => 1,
      "unaffected_sha256" => ObservationReplacements.digest(before.transform_values { |v| v.reject { |id, _| selected.include?(id) } }) }
    @overlay = ObservationReplacements.new(nil, [])
    @overlay.instance_variable_set(:@entries, { "batch" => { campaign: { "ids" => selected }, guard: guard,
      rows: @rows.take(2).map { |r| r.merge("value" => "new") },
      validations: { @ids[0] => { "passed" => true }, @ids[1] => { "passed" => false } },
      records: { @ids[0] => { "time" => 20.0 } } } })
  end

  def apply
    @overlay.apply!({ "id" => "batch" }, @validations, @records, @rows)
  end

  def test_replaces_exact_scope_and_removes_new_validation_failure
    unaffected = Marshal.dump([@rows.last, @validations.fetch(@ids.last), @records.fetch(@ids.last)])
    apply
    assert_equal %w[new new old], @rows.map { |r| r.fetch("value") }
    assert_equal 20.0, @records.fetch(@ids.first).fetch("time")
    refute @records.key?(@ids[1])
    refute @validations.fetch(@ids[1]).fetch("passed")
    assert_equal unaffected, Marshal.dump([@rows.last, @validations.fetch(@ids.last), @records.fetch(@ids.last)])
  end

  def test_rejects_modified_unrelated_data
    @records.fetch(@ids.last)["time"] = 9.0
    assert_match(/baseline changed/, assert_raises(RuntimeError) { apply }.message)
  end

  def test_rejects_missing_original_observation
    @rows.shift
    assert_match(/outside original/, assert_raises(RuntimeError) { apply }.message)
  end

  def test_cannot_apply_twice
    apply
    assert_match(/baseline changed/, assert_raises(RuntimeError) { apply }.message)
  end

  def test_other_campaign_is_untouched
    before = Marshal.dump([@rows, @validations, @records])
    @overlay.apply!({ "id" => "other" }, @validations, @records, @rows)
    assert_equal before, Marshal.dump([@rows, @validations, @records])
  end
end
