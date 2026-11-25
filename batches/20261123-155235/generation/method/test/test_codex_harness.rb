# frozen_string_literal: true
require "minitest/autorun"
require_relative "../lib/codex_harness"

class CodexHarnessTest < Minitest::Test
  def setup
    source = File.read(File.expand_path("../experiment.rb", __dir__))
    @base = source[/^PARAMS_CODEX = '([^']+)'$/, 1]
    raise "Missing authoritative Codex restrictions" unless @base
    @profiles = source.scan(/^    "([^"]+)" => "(?:low|medium|high|xhigh|max|ultra)",$/).flatten
  end

  def test_existing_profiles_are_identical
    (@profiles - ["gpt-6.1-terra-ultra"] + ["unknown"]).each do |profile|
      assert_equal Shellwords.split(@base), CodexHarness.flags(@base, profile: profile), profile
    end
  end

  def test_ultra_changes_only_delegation
    expected = @base.gsub(" --disable multi_agent_v2", "").gsub(" --disable multi_agent", "")
    assert_equal Shellwords.split(expected) + ["--enable", "multi_agent"],
      CodexHarness.flags(@base, profile: "gpt-6.1-terra-ultra")
    assert_includes @profiles, "gpt-6.1-terra-ultra"
  end

  def test_gpt62_medium_profiles_keep_single_agent_restrictions
    source = File.read(File.expand_path("../experiment.rb", __dir__))
    %w[astra sol].each do |family|
      profile = "gpt-6.2-#{family}-medium"
      assert_includes @profiles, profile
      assert_includes source, %Q{"#{profile}" => "gpt-6.2-#{family}"}
      assert_equal Shellwords.split(@base), CodexHarness.flags(@base, profile: profile)
      %w[multi_agent multi_agent_v2 browser_use plugins].each do |feature|
        assert_includes CodexHarness.flags(@base, profile: profile).each_cons(2).to_a, ["--disable", feature]
      end
    end
  end

  def test_fail_closed_when_base_policy_changes
    %w[multi_agent multi_agent_v2].each do |feature|
      changed = Shellwords.split(@base)
      index = changed.index(feature)
      changed.slice!(index - 1, 2)
      assert_raises(RuntimeError) { CodexHarness.flags(Shellwords.join(changed), profile: "gpt-6.1-terra-ultra") }
    end
  end
end
