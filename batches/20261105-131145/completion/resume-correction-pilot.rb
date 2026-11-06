# frozen_string_literal: true
require_relative 'observer-pipeline-v3/tools/timing_audit/lib/timing_audit'
campaign = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation'
root = '/home/petert/llm_timing_audit/20261106-terra61-ultra-codex-cross-review-sol61'
progress_path = File.join(campaign, 'correction-pilot-progress.json')
progress = JSON.parse(File.read(progress_path))
raise 'Unexpected stopped stage' unless progress.values_at('phase', 'stopped_phase') == %w[stopped prepare_proposals] &&
  progress.fetch('error') == 'KeyError: key not found: "roots"'
proposals = '/home/petert/llm_timing_fixes/20261106-terra61-ultra-codex-proposals'
raise 'Proposals already started' if File.exist?(proposals)
receipt_path = File.join(campaign, 'correction-pilot-resume.json')
raise 'Resume already recorded' if File.exist?(receipt_path)
metadata_path = File.join(root, 'final/metadata.yaml')
metadata = YAML.safe_load_file(metadata_path)
raise 'Unexpected existing roots' if metadata.key?('roots')
decisions_path = File.join(root, 'final/decisions.jsonl')
raise 'Scientific decisions changed' unless metadata.fetch('decisions_sha256') == TimingAudit.sha256_file(decisions_path)
before = TimingAudit.sha256_file(metadata_path)
backup = File.join(root, 'final/metadata-before-root-binding.yaml')
raise 'Metadata backup exists' if File.exist?(backup)
FileUtils.cp(metadata_path, backup)
metadata['roots'] = { 'primary' => '/home/petert/llm_timing_audit/20261106-terra61-ultra-codex-qtclustering',
  'priority_review' => nil, 'adjudication' => root }
TimingAudit.atomic_write(metadata_path, YAML.dump(metadata))
FileUtils.cp(progress_path, File.join(campaign, 'correction-pilot-progress-before-resume.json'))
driver = File.join(__dir__, 'correction-pilot-driver.rb')
unit = 'llm-terra61-ultra-codex-correction-pilot-20261106.service'
log = File.join(campaign, 'correction-pilot-driver.log')
raise 'Resume launch failed' unless system('systemd-run', '--user', '--collect', "--unit=#{unit}",
  '--description=Terra Ultra timing-only correction pilot (metadata handoff repaired)',
  "--property=WorkingDirectory=#{__dir__}",
  '--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin',
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", '/usr/bin/ruby', driver)
properties = TimingAudit.capture!('systemctl', '--user', 'show', unit, '-p', 'ActiveState', '-p', 'InvocationID')
raise 'Resumed service did not start' unless properties.include?('ActiveState=active')
receipt = { 'resumed_at' => TimingAudit.utc_now, 'unit' => unit, 'properties' => properties,
  'metadata_before_sha256' => before, 'metadata_after_sha256' => TimingAudit.sha256_file(metadata_path),
  'decisions_sha256' => TimingAudit.sha256_file(decisions_path), 'driver_sha256' => TimingAudit.sha256_file(driver),
  'script_sha256' => TimingAudit.sha256_file(__FILE__), 'prior_model_calls' => 0,
  'policy' => 'Add the established audit-root provenance field required by the correction inventory. No scientific verdicts, sources or review responses changed; no model call repeated.' }
TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(receipt)
