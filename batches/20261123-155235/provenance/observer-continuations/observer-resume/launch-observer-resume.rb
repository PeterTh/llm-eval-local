# frozen_string_literal: true
require 'json'
require 'open3'
require 'time'
require 'digest'
require_relative 'observer-pipeline/lib/local_evaluation'

scratch = __dir__
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
evidence = File.join(campaign, 'observer-resume')
resume = JSON.parse(File.read(File.join(evidence, 'resume.json')))
destination = File.join(evidence, 'launch.json')
raise 'Resume already launched' if File.exist?(destination)
unit = 'llm-gpt62-medium-validation-20261125.service'
state, = Open3.capture2('systemctl', '--user', 'show', unit, '--property=ActiveState', '--value')
raise 'Validation already active' if %w[active activating reloading].include?(state.strip)
raise 'Generation account active' if system('pgrep', '-u', 'llmtest', out: File::NULL)
command = ['/usr/bin/ruby', File.join(scratch, 'local-evaluation-driver.rb'), 'validate',
  '--run-dir=' + resume.fetch('successor_run'), '--dry-run']
stdout, stderr, status = Open3.capture3(*command)
raise "Resume dry run failed: #{stdout} #{stderr}" unless status.success? &&
  stdout.lines.first.strip == 'Validation dry run: 414 pending of 440 selected IDs'
LocalEvaluation.atomic_write(File.join(evidence, 'dry-run.log'), stdout + stderr)
LocalEvaluation.atomic_write(File.join(evidence, File.basename(__FILE__)), File.binread(__FILE__))
log = File.join(campaign, 'validation-driver.log')
args = ['systemd-run', '--user', '--collect', '--unit=' + unit,
  '--description=GPT 6.2 native validation with binary-scoped streamed-output observer',
  '--property=WorkingDirectory=' + File.join(scratch, 'observer-pipeline'),
  '--property=StandardOutput=append:' + log, '--property=StandardError=append:' + log,
  '/usr/bin/ruby', File.join(scratch, 'validation-driver.rb')]
raise 'Resume launch failed' unless system(*args)
state, stderr, status = Open3.capture3('systemctl', '--user', 'show', unit,
  '--property=ActiveState,SubState,MainPID,InvocationID,ExecMainStartTimestamp')
raise stderr unless status.success? && state.include?('ActiveState=active')
report = { 'launched_at' => Time.now.utc.iso8601, 'command' => args, 'unit_state' => state,
  'resume_sha256' => LocalEvaluation.sha256_file(File.join(evidence, 'resume.json')),
  'dry_run_sha256' => LocalEvaluation.sha256_file(File.join(evidence, 'dry-run.log')),
  'reused_validations' => 26, 'pending_validations' => 414, 'benchmark_runs' => 0,
  'publication_hold' => 'Discuss the default visible model set with the user before any website change.' }
LocalEvaluation.atomic_write(destination, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
