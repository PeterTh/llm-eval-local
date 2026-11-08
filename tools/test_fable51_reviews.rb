# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'digest'

class Fable51ReviewsTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('fable-review-test-', '/tmp')
    @script = File.join(@root, 'analysis/src/check_fable51_reviews.rb')
    FileUtils.mkdir_p(File.dirname(@script))
    FileUtils.cp(File.expand_path('../analysis/src/check_fable51_reviews.rb', __dir__), @script)
    @id = 'matmul_claude-fable-5.1-cc-medium_omp_r1'
    @peer = { 'id' => @id, 'median_ms' => 100.0, 'times_ms' => [99, 100, 100, 101, 102],
      'source_path' => "20261011-092100/#{@id}", 'source_commit' => 'a' * 40 }
    @context = { 'reviews' => {}, 'source_pins' => {}, 'benchmark_inputs' => {} }
    @winners = []
  end

  def teardown
    FileUtils.remove_entry_secure(@root)
  end

  def json(relative, data)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(data))
  end

  def add_review
    @winners << @peer.dup
    note = "analysis/notes/individual/#{@id}.md"
    @context['reviews'][@id] = @peer.merge('note_path' => note, 'top' => [@peer.dup], 'previous' => @peer.dup)
    @context['source_pins'][@id] = @peer.slice('source_path', 'source_commit').transform_keys do |key|
      key == 'source_path' ? 'path' : 'commit'
    end.merge('files' => { 'matmul/matmul.cpp' => 'b' * 64 })
    @note_path = File.join(@root, note)
    FileUtils.mkdir_p(File.dirname(@note_path))
    @note = "# `#{@id}`\n\n" + ['Scope', 'Finding', 'Close-group comparison', 'Correctness and timing', 'Interpretation']
      .map { |section| "## #{section}\n\nFixture.\n\n" }.join
  end

  def check
    json('release/winners.json', @winners)
    json('analysis/notes/2026-11-08-fable51-medium-winner-context.json', @context)
    File.write(@note_path, @note) if @note_path
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, @script)
    [status.success?, stdout + stderr]
  end

  def test_no_new_winners_is_a_complete_review_set
    success, log = check
    assert success, log
  end

  def test_current_and_later_displaced_reviews_are_preserved
    add_review
    success, log = check
    assert success, log
    @winners.clear
    success, log = check
    assert success, log
  end

  def test_rejects_unreviewed_current_winner
    @winners << @peer
    success, log = check
    refute success
    assert_includes log, 'Unreviewed Fable winner'
  end

  def test_rejects_changed_measurement
    add_review
    @winners.first['median_ms'] = 90.0
    success, log = check
    refute success
    assert_includes log, 'Reviewed measurement changed'
  end

  def test_rejects_missing_source_pins_and_filler
    add_review
    @context['source_pins'][@id]['files'] = {}
    success, log = check
    refute success
    assert_includes log, 'Missing pinned source files'
    @context['source_pins'][@id]['files'] = { 'matmul/matmul.cpp' => 'b' * 64 }
    @note += "## Limits and release decision\n\nFiller.\n"
    success, log = check
    refute success
    assert_includes log, 'Obsolete review filler'
  end
end
