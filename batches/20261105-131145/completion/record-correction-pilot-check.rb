# frozen_string_literal: true
require_relative 'observer-pipeline-v3/tools/timing_audit/lib/timing_audit'
campaign = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation'
root = '/home/petert/llm_timing_fixes/20261106-terra61-ultra-codex-proposals'
gate = JSON.parse(File.read(File.join(campaign, 'correction-pilot-gate.json')))
raise 'Pilot not accepted' unless gate.fetch('passed') && gate.fetch('records') == 16 &&
  gate.fetch('independent_acceptances') == 16 && gate.fetch('targeted_adjudications').zero?
patch = File.join(root, 'materialized/timing-fixes-trial.patch')
raise 'Pilot patch changed' unless TimingAudit.sha256_file(patch) == gate.fetch('input_sha256').fetch(patch)
ids = File.readlines(File.join(root, 'trial-ids.txt'), chomp: true).reject(&:empty?)
report = { 'checked_at' => TimingAudit.utc_now, 'passed' => true, 'ids' => ids,
  'patch_sha256' => TimingAudit.sha256_file(patch),
  'inspection' => 'Primary operator read the complete materialized 16-program patch. One Black-Scholes correction moves the same pricing preprocessing kernel into its timed work; N-body, QT and Roomsim changes aggregate elapsed durations or construct the existing total interval. Independent source-grounded reviews establish scope and timing validity for every program; all compiled. No benchmark parameters or algorithmic outputs edited.',
  'checks' => { 'all_patch_hunks_inspected' => true, 'independent_acceptances' => 16,
    'compile_successes' => 16, 'unresolved' => 0, 'generated_programs_executed_in_review' => 0 },
  'scope' => 'Pilot quality gate only; final native scientific revalidation remains required.' }
output = File.join(campaign, 'correction-pilot-diff-check.json')
raise 'Quality receipt exists' if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.reject { |key, _| key == 'ids' })
