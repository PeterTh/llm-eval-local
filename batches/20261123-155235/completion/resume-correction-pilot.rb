# frozen_string_literal: true
require_relative 'observer-pipeline-v5/tools/timing_audit/lib/timing_audit'
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
repair = JSON.parse(File.read(File.join(campaign, 'correction-root-binding-repair.json')))
raise 'Audit binding changed' unless repair.fetch('audit_report_after_sha256') == TimingAudit.sha256_file(File.join(campaign, 'audit-completion-review.json'))
raise 'Unexpected prior activity' unless repair.fetch('prior_model_calls').zero? && repair.fetch('program_changes').zero?
raise 'Proposals already started' if File.exist?('/home/petert/llm_timing_fixes/20261125-gpt62-astra-sol-medium-proposals')
receipt_path = File.join(campaign, 'correction-pilot-resume.json')
raise 'Resume already recorded' if File.exist?(receipt_path)
cli = JSON.parse(File.read(File.join(campaign, 'audit-pilot-launch.json')))
raise 'Review CLI changed' unless File.realpath('/home/petert/.local/bin/codex') == cli.fetch('review_cli_path') && TimingAudit.sha256_file(cli.fetch('review_cli_path')) == cli.fetch('review_cli_sha256')
driver = File.join(__dir__, 'correction-pilot-driver.rb')
original_launch = JSON.parse(File.read(File.join(campaign, 'correction-pilot-launch.json')))
raise 'Pilot driver changed' unless TimingAudit.sha256_file(driver) == original_launch.fetch('driver_sha256')
unit = 'llm-gpt62-medium-correction-pilot-20261125.service'
state, = Open3.capture2('systemctl', '--user', 'show', unit, '--property=ActiveState', '--value')
raise 'Pilot already running' if %w[active activating reloading].include?(state.strip)
log = File.join(campaign, 'correction-pilot-driver.log')
raise 'Resume launch failed' unless system('systemd-run', '--user', '--collect', "--unit=#{unit}",
  '--description=GPT 6.2 timing-only correction pilot (provenance handoff repaired)',
  "--property=WorkingDirectory=#{__dir__}", '--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin',
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", '/usr/bin/ruby', driver)
properties = TimingAudit.capture!('systemctl', '--user', 'show', unit, '-p', 'ActiveState', '-p', 'InvocationID', '-p', 'MainPID', '-p', 'ExecMainStartTimestamp')
raise 'Resumed service did not start' unless properties.include?('ActiveState=active')
receipt = { 'resumed_at' => TimingAudit.utc_now, 'unit' => unit, 'properties' => properties,
  'driver_sha256' => TimingAudit.sha256_file(driver), 'repair_receipt_sha256' => TimingAudit.sha256_file(File.join(campaign, 'correction-root-binding-repair.json')),
  'audit_report_sha256' => repair.fetch('audit_report_after_sha256'), 'prior_model_calls' => 0,
  'policy' => 'Resume the same established pilot after metadata-only handoff repair; no source, scientific decision, model response or program run is repeated.' }
TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(receipt)
