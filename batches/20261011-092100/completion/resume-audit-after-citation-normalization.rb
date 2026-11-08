# frozen_string_literal: true
require_relative 'experiment/tools/timing_audit/lib/timing_audit'
require_relative 'audit-citation-normalization'
campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
unit = 'llm-fable51-medium-timing-full-20261107.service'
output = File.join(campaign, 'audit-format-recovery-resume-launch.json')
raise 'Already resumed' if File.exist?(output)
summary = JSON.parse(File.read(File.join(campaign, 'audit-citation-normalization.json')))
raise 'Receipt changed' unless TimingAudit.sha256_file(summary.fetch('receipt')) == summary.fetch('receipt_sha256')
AuditCitationNormalization.verify!(summary.fetch('receipt'))
raise 'Old audit still active' unless TimingAudit.capture!('systemctl', '--user', 'show', unit, '--property=ActiveState', '--value').strip == 'inactive'
driver = File.join(__dir__, 'audit-full-driver-policy.rb')
policy = JSON.parse(File.read(File.join(campaign, 'review-policy.json')))
raise 'Original full driver changed' unless TimingAudit.sha256_file(driver) == policy.fetch('driver_sha256')
log = File.join(campaign, 'audit-full-after-format-recovery.log')
raise 'Resume log already exists' if File.exist?(log)
%w[audit-citation-normalization.rb normalize-one-audit-citation.rb test-audit-citation-normalization.rb resume-audit-after-citation-normalization.rb verify-audit-completion.rb].each { |name| FileUtils.cp(File.join(__dir__, name), campaign) }
TimingAudit.capture!('systemd-run', '--user', '--collect', "--unit=#{unit}",
  '--description=Fable static timing review continuation with all primary responses retained',
  "--property=WorkingDirectory=#{__dir__}",
  '--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin',
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", '/usr/bin/ruby', driver)
properties = TimingAudit.capture!('systemctl', '--user', 'show', unit,
  '-p', 'ActiveState', '-p', 'SubState', '-p', 'InvocationID', '-p', 'ExecMainPID').lines.to_h { |line| line.strip.split('=', 2) }
raise 'Audit continuation did not start' unless properties.fetch('ActiveState') == 'active'
report = { 'resumed_at' => TimingAudit.utc_now, 'unit' => unit, 'properties' => properties,
  'driver_sha256' => TimingAudit.sha256_file(driver), 'normalization_receipt_sha256' => summary.fetch('receipt_sha256'),
  'all_primary_responses_reused' => 110, 'scientific_review_contract_changed' => false,
  'source_programs_or_native_evaluation_changed' => false }
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
