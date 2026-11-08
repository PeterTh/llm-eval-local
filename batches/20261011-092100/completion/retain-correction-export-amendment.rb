# frozen_string_literal: true
require 'json'
require 'digest'
require 'time'
require 'fileutils'

campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
target = File.join(campaign, 'export-completed-batch.rb')
source = File.join(__dir__, 'export-completed-batch.rb')
before_sha = 'd2b5b43e4d8fcf9e35e16da59a64a470f91e70941fa3c0b536bebc14502f5305'
raise 'Previous export driver changed' unless Digest::SHA256.file(target).hexdigest == before_sha
raise 'Revised export driver invalid' unless system('ruby', '-c', source)
gate_path = File.join(campaign, 'correction-history-export-check.json')
gate = JSON.parse(File.read(gate_path))
helper = File.join(__dir__, 'artifact/tools/export_timing_revision_evidence.rb')
raise 'History export not checked' unless gate.fetch('passed') && gate.fetch('exporter_sha256') == Digest::SHA256.file(helper).hexdigest
backup = File.join(campaign, 'export-completed-batch-before-correction-history.rb')
receipt = File.join(campaign, 'correction-export-amendment.json')
raise 'Export amendment exists' if File.exist?(backup) || File.exist?(receipt)
FileUtils.cp(target, backup)
FileUtils.cp(source, target)
FileUtils.cp(__FILE__, campaign)
record = {
  'amended_at' => Time.now.utc.iso8601, 'before_sha256' => before_sha,
  'after_sha256' => Digest::SHA256.file(source).hexdigest,
  'history_export_check_sha256' => Digest::SHA256.file(gate_path).hexdigest,
  'history_exporter_sha256' => Digest::SHA256.file(helper).hexdigest,
  'backup' => backup,
  'policy' => 'Add compact superseded correction/review evidence and its tested export receipt. The already-tested audit/generation supplement, native corrections export, validation and benchmark procedures are unchanged.'
}
File.write(receipt, JSON.pretty_generate(record) + "\n")
puts JSON.pretty_generate(record)
