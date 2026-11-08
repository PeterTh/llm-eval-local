# frozen_string_literal: true
require 'json'
require 'digest'
module AuditCitationNormalization
  module_function
  # Syntax only: split a list of independently specified closed line ranges.
  # Never combine ranges into a broader interval or edit the finding text.
  def normalize(raw)
    result = JSON.parse(JSON.generate(raw))
    edits = []
    result['evidence'] = raw.fetch('evidence').each_with_index.flat_map do |entry, index|
      value = entry.fetch('lines')
      next [entry.dup] if value.match?(/\A\d+(?:-\d+)?\z/)
      raise 'Not an unambiguous citation list' unless value.match?(/\A\d+(?:-\d+)?(?:\s*[,;]\s*\d+(?:-\d+)?)+\z/)
      ranges = value.split(/\s*[,;]\s*/)
      edits << { 'entry_index' => index, 'original_lines' => value, 'separate_ranges' => ranges }
      ranges.map { |range| entry.merge('lines' => range) }
    end
    raise 'No list normalization required' if edits.empty?
    raise 'Non-evidence content changed' unless result.reject { |key, _| key == 'evidence' } == raw.reject { |key, _| key == 'evidence' }
    [result, edits]
  end

  def verify!(receipt_path)
    report = JSON.parse(File.read(receipt_path))
    report.fetch('retained_files_sha256').each do |path, digest|
      raise "Normalization evidence changed: #{path}" unless Digest::SHA256.file(path).hexdigest == digest
    end
    events = File.readlines(report.fetch('events_path')).map { |line| JSON.parse(line) }
    raw = events.filter_map do |event|
      item = event['item']
      JSON.parse(item.fetch('text')) if event['type'] == 'item.completed' && item && item['type'] == 'agent_message'
    end.last
    raise 'Retained raw response differs from actual event' unless raw == JSON.parse(File.read(report.fetch('raw_response_path')))
    normalized, edits = normalize(raw)
    raise 'Normalization changed meaning or cited spans' unless edits == report.fetch('edits') && normalized == JSON.parse(File.read(report.fetch('result_path')))
    raise 'Normalized result changed' unless Digest::SHA256.file(report.fetch('result_path')).hexdigest == report.fetch('result_sha256')
    true
  end
end
