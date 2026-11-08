# frozen_string_literal: true
require_relative 'experiment/tools/timing_audit/lib/timing_audit'
require_relative 'audit-citation-normalization'
root = '/home/petert/llm_timing_audit/20261107-fable51-medium'
campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
id = 'qtclustering_claude-fable-5.1-cc-medium_hybrid_r3'
directory = File.join(root, 'operator-citation-normalization', id)
raise 'Normalization already exists' if File.exist?(directory)
result_path = File.join(root, 'results', id + '.json')
raise 'Never overwrite an accepted review' if File.exist?(result_path)
attempt = File.join(root, 'logs', id, 'attempt-04')
events_path = File.join(attempt, 'events.jsonl')
metadata_path = File.join(attempt, 'metadata.yaml')
metadata = YAML.safe_load_file(metadata_path)
raise 'Wrong invocation identity or outcome' unless metadata.values_at('program_id', 'model', 'reasoning_effort', 'exit_code', 'timed_out') == [id, 'gpt-5.6-luna', 'high', 0, false]
raise 'Events changed' unless metadata.fetch('events_sha256') == TimingAudit.sha256_file(events_path)
TimingAudit.verify_static_events!(events_path)
records = TimingAudit.load_jsonl(File.join(root, 'inventory.jsonl'))
record = records.find { |row| row.fetch('id') == id }
raise 'Source binding changed' unless record.fetch('source_digest') == metadata.fetch('source_digest')
raw_text = TimingAudit.load_jsonl(events_path).filter_map do |event|
  item = event['item']
  item.fetch('text') if event['type'] == 'item.completed' && item && item['type'] == 'agent_message'
end.last
raw = JSON.parse(raw_text)
validator = TimingAudit::ResultValidator.new(records)
begin
  validator.validate!(raw, expected_id: id)
  raise 'Response was not schema-invalid'
rescue RuntimeError => error
  raise unless error.message == 'Invalid evidence line range'
end
normalized, edits = AuditCitationNormalization.normalize(raw)
validator.validate!(normalized, expected_id: id)
raise 'Unexpected normalization scope' unless edits.size == 1 && edits.first.fetch('original_lines') == '1218-1220, 1282-1285'
retained = Dir[File.join(root, 'results/*.json')].to_h { |path| [path, TimingAudit.sha256_file(path)] }
raise 'Unexpected prior response coverage' unless retained.size == 109
FileUtils.mkdir_p(directory)
old_metadata = File.join(directory, 'metadata-before-normalization.yaml')
FileUtils.cp(metadata_path, old_metadata)
raw_path = File.join(directory, 'raw-response.json')
TimingAudit.atomic_write(raw_path, raw_text + "\n")
%w[audit-citation-normalization.rb test-audit-citation-normalization.rb normalize-one-audit-citation.rb].each { |name| FileUtils.cp(File.join(__dir__, name), directory) }
before = File.join(directory, 'progress-before-normalization.json')
FileUtils.cp(File.join(campaign, 'audit-full-progress.json'), before)
serialized = JSON.pretty_generate(normalized) + "\n"
receipt = File.join(directory, 'normalization.json')
report = {
  'normalized_at' => TimingAudit.utc_now, 'program_id' => id,
  'operation' => 'Split a comma-separated citation list into two evidence entries, retaining the exact path, finding text and individual cited spans.',
  'scientific_verdict_or_claim_changed' => false, 'new_model_invocation' => false,
  'events_path' => events_path, 'raw_response_path' => raw_path, 'result_path' => result_path,
  'result_sha256' => TimingAudit.sha256_bytes(serialized), 'edits' => edits,
  'retained_files_sha256' => [events_path, old_metadata, raw_path, before, File.join(directory, 'audit-citation-normalization.rb')].to_h { |path| [path, TimingAudit.sha256_file(path)] },
  'prior_accepted_results_sha256' => retained,
  'metadata_annotation' => 'Original attempt metadata is retained verbatim. The existing attempt metadata is annotated with this explicit operator normalization, not represented as a new/raw model response.',
  'independent_review_still_required' => true, 'program_execution' => false, 'program_changes' => false
}
TimingAudit.atomic_write(receipt, JSON.pretty_generate(report) + "\n")
metadata['result_sha256'] = report.fetch('result_sha256')
metadata['static_only_verified'] = true
metadata['operator_citation_normalization'] = { 'receipt' => receipt, 'receipt_sha256' => TimingAudit.sha256_file(receipt),
  'original_metadata_sha256' => TimingAudit.sha256_file(old_metadata), 'raw_model_response_preserved' => true,
  'new_model_invocation' => false, 'response_is_syntax_normalized' => true }
TimingAudit.atomic_write(result_path, serialized)
TimingAudit.atomic_write(metadata_path, YAML.dump(metadata))
AuditCitationNormalization.verify!(receipt)
retained.each { |path, digest| raise 'Prior result changed' unless TimingAudit.sha256_file(path) == digest }
TimingAudit::AuditVerifier.new(root, 'full').run
TimingAudit.atomic_write(File.join(campaign, 'audit-citation-normalization.json'), JSON.pretty_generate({
  'verified_at' => TimingAudit.utc_now, 'receipt' => receipt, 'receipt_sha256' => TimingAudit.sha256_file(receipt),
  'normalized_attempt_metadata_sha256' => TimingAudit.sha256_file(metadata_path),
  'retained_results_unchanged' => 109, 'primary_results_now_complete' => 110,
  'scientific_review_contract_changed' => false, 'raw_responses_preserved' => true
}) + "\n")
puts JSON.pretty_generate(report.slice('program_id', 'operation', 'scientific_verdict_or_claim_changed', 'new_model_invocation', 'edits'))
