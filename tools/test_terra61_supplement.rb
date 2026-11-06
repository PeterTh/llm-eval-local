# frozen_string_literal: true
require "minitest/autorun"
require_relative "export_terra61_supplement"

class Terra61SupplementTest < Minitest::Test
  def test_default_medium_campaign_is_unchanged
    assert_equal "20261028-200951", Terra61Supplement::BATCH
    configuration = Terra61Supplement::CAMPAIGNS.fetch(Terra61Supplement::BATCH)
    assert_equal Terra61Supplement::ORIGINAL, configuration.fetch("original")
    assert_equal "gpt-6.1-terra-medium", configuration.fetch("profile")
    assert_equal "medium", configuration.fetch("effort")
    assert_equal "20261029-terra61-codex", configuration.fetch("audit")
    assert configuration.frozen?
  end

  def test_xhigh_has_separate_source_and_evidence_identity
    configuration = Terra61Supplement::CAMPAIGNS.fetch("20261102-030935")
    assert_equal "c070881d4b6186c32117ecd339e87d6f32db77e7", configuration.fetch("original")
    assert_equal "gpt-6.1-terra-xhigh", configuration.fetch("profile")
    assert_equal "xhigh", configuration.fetch("effort")
    assert_equal "terra61-codex-xhigh", configuration.fetch("campaign_suffix")
    assert_equal "20261102-terra61-xhigh-codex", configuration.fetch("audit")
    assert configuration.frozen?
  end

  def test_unknown_campaign_rejected_before_any_export
    assert_raises(KeyError) do
      Terra61Supplement.run(root: "/nonexistent", home: "/nonexistent", phase: "audit", batch_id: "unknown")
    end
  end

  def test_ultra_has_separate_tree_accounting_and_source_identity
    configuration = Terra61Supplement::CAMPAIGNS.fetch('20261105-131145')
    assert_equal 'e8a5a56facfc3feedc8de8dc0cca41af590acd66', configuration.fetch('original')
    assert_equal 'gpt-6.1-terra-ultra', configuration.fetch('profile')
    assert_equal 'ultra', configuration.fetch('effort')
    assert_equal true, configuration.fetch('tree_usage')
    assert_equal '20261106-terra61-ultra-codex', configuration.fetch('audit')
    assert configuration.frozen?
    refute Terra61Supplement::CAMPAIGNS.fetch('20261102-030935').fetch('tree_usage', false)
  end
end
