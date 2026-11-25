# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'observer_continuations'

class ObserverContinuationsTest < Minitest::Test
  def setup
    @root = File.expand_path('..', __dir__)
    @campaign = JSON.parse(File.read(File.join(@root, 'release/catalog.json'))).fetch('campaigns').find { |c| c['id'] == '20261123-155235' }
    @index = JSON.parse(File.read(File.join(@root, @campaign.fetch('observer_continuations'))))
  end

  def verify
    ObserverContinuations.verify(root: @root, campaign: @campaign, index: @index)
  end

  def test_complete_deduplicated_chain
    assert_equal 4, @index.fetch('phases').size
    assert_equal 5, @index.fetch('method_layouts').size
    assert verify
  end

  def test_tampered_receipt_and_unsafe_paths_fail
    binding = @index.fetch('phases').values.first.fetch('receipt')
    binding['sha256'] = '0' * 64
    assert_raises(RuntimeError) { verify }
    binding['path'] = '../escape.json'
    assert_raises(RuntimeError) { verify }
  end

  def test_source_and_final_method_are_bound
    @campaign['source_commit'] = '0' * 40
    assert_raises(RuntimeError) { verify }
  end
end
