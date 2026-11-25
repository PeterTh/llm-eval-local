# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'gpt62_generation_evidence'

class Gpt62GenerationEvidenceTest < Minitest::Test
  def fixture
    profiles = Gpt62GenerationEvidence::PROFILES
    counters = { 'input_tokens' => 100, 'cached_input_tokens' => 80, 'output_tokens' => 10,
      'reasoning_output_tokens' => 3, 'total_tokens' => 110, 'cache_write_input_tokens' => 0 }
    observations = profiles.map.with_index do |profile, index|
      { 'id' => "run#{index}", 'model' => profile.delete_suffix('-medium'), 'reasoning_effort' => 'medium' }
    end
    usage = observations.to_h do |observation|
      id = observation.fetch('id')
      [id, { 'batch' => Gpt62GenerationEvidence::BATCH, 'run_id' => id, 'session_id' => id,
        'session_sha256' => 'a' * 64, 'usage' => counters.dup }]
    end
    requests = usage.map do |id, original|
      { 'batch' => Gpt62GenerationEvidence::BATCH, 'run_id' => id, 'session_id' => id,
        'session_sha256' => 'a' * 64, 'exact_final_record_sha256' => Digest::SHA256.hexdigest(JSON.generate(original)),
        'total_usage' => counters.dup, 'request_count' => 1, 'max_request_input_tokens' => 100,
        'requests' => [{ 'response_id_sha256' => 'b' * 64, 'usage' => counters.dup }] }
    end
    audit = { 'context_threshold_input_tokens' => 272_000,
      'profiles' => profiles.to_h { |profile| [profile, { 'requests' => 1, 'max_request_input_tokens' => 100,
        'total_usage' => counters.dup, 'by_context_tier' => { 'long' => { 'requests' => 0 } } }] } }
    reference = { 'status' => 'selected_by_user', 'context_threshold_input_tokens' => 272_000,
      'selected' => { 'provider' => 'OpenAI', 'service_tier' => 'default', 'pricing_tier' => 'standard', 'background_discount' => false },
      'profiles' => profiles.to_h do |profile|
        multiplier = profile.include?('astra') ? 4 : 1
        cost = BigDecimal('0.000148') * multiplier
        [profile, { 'short_rates_usd_per_million' => { 'input' => 2 * multiplier,
          'cached_input' => 0.1 * multiplier, 'output' => 10 * multiplier },
          'cost_summary' => { 'total_usd' => cost.to_s('F'), 'mean_usd_per_observation' => (cost / 220).to_s('F') } }]
      end }
    [requests, usage, observations, audit, reference]
  end

  def test_cached_input_and_reasoning_are_not_double_counted
    result = Gpt62GenerationEvidence.verify_requests!(*fixture)
    assert_equal 2, result.fetch('requests')
    assert_equal '0.000592', result.fetch('standard_cost_totals_usd').fetch('gpt-6.2-astra-medium')
    assert_equal '0.000148', result.fetch('standard_cost_totals_usd').fetch('gpt-6.2-sol-medium')
  end

  def test_duplicate_native_request_is_rejected
    values = fixture
    row = values.first.first
    row['requests'] << Marshal.load(Marshal.dump(row.fetch('requests').first))
    row['request_count'] = 2
    assert_match(/Duplicate request identity/, assert_raises(RuntimeError) { Gpt62GenerationEvidence.verify_requests!(*values) }.message)
  end

  def test_unknown_context_surcharge_is_not_silently_ignored
    values = fixture
    values.first.first.fetch('requests').first.fetch('usage')['input_tokens'] = 272_001
    values.first.first.fetch('requests').first.fetch('usage')['total_tokens'] = 272_011
    assert_match(/Unexpected long-context/, assert_raises(RuntimeError) { Gpt62GenerationEvidence.verify_requests!(*values) }.message)
  end

  def test_background_discount_is_not_selected
    values = fixture
    values.last.fetch('selected')['background_discount'] = true
    assert_match(/Wrong selected pricing/, assert_raises(RuntimeError) { Gpt62GenerationEvidence.verify_requests!(*values) }.message)
  end

  def test_changed_final_record_binding_is_rejected
    values = fixture
    values.first.first['exact_final_record_sha256'] = '0' * 64
    assert_match(/Request provenance differs/, assert_raises(RuntimeError) { Gpt62GenerationEvidence.verify_requests!(*values) }.message)
  end

  def test_paths_must_stay_within_retained_evidence
    %w[/tmp/x ../x a/../x a/./x].each do |path|
      assert_raises(RuntimeError) { Gpt62GenerationEvidence.safe_relative!(path) }
    end
    assert_equal 'pricing/reference.json', Gpt62GenerationEvidence.safe_relative!('pricing/reference.json')
  end
end
