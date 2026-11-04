require 'json'
require 'digest'
require 'open3'

# Read-only reconstruction from retained evidence; does not execute benchmark programs.
root = File.expand_path('../../..', __dir__)
evidence_file = ARGV.find { |a| !a.start_with?('--') } || File.join(root, 'analysis/notes/2026-11-03-winner-validity/evidence.json')
evidence = JSON.parse(File.read(evidence_file))
expected_digest = File.read(File.join(File.dirname(evidence_file), 'evidence.sha256')).split.first
raise 'Evidence digest mismatch' unless Digest::SHA256.file(evidence_file).hexdigest == expected_digest
def git(repo, *args)
  out, err, status = Open3.capture3('git', '-C', repo, *args)
  raise err unless status.success?
  out
end
release = ENV.fetch('WINNER_AUDIT_RELEASE', root)
commit = evidence.fetch('release_commit')
winners_bytes = git(release, 'show', "#{commit}:release/winners.json")
raise 'Frozen winner list digest mismatch' unless Digest::SHA256.hexdigest(winners_bytes) == evidence.fetch('release_winners_sha256')
expected = JSON.parse(winners_bytes).map { |w| [w.fetch('cell'), w.fetch('id')] }.sort
actual = evidence.fetch('winners').map { |w| [w.fetch('cell'), w.fetch('id')] }.sort
raise 'Winner coverage mismatch' unless expected == actual && actual.size == 44 && actual.map(&:first).uniq.size == 44
comparator = git(release, 'show', "#{commit}:method/pipeline/validation_helper.rb")
raise 'Comparator changed' unless Digest::SHA256.hexdigest(comparator) == evidence.fetch('method_sha256').fetch('validation_helper.rb')
eval(comparator, TOPLEVEL_BINDING, 'frozen_validation_helper.rb')
checks = evidence.fetch('checks')
raise 'Duplicate checks' unless checks.map { |c| c.fetch('check_id') }.uniq.size == checks.size
by_check = checks.to_h { |c| [c.fetch('check_id'), c] }
builds = evidence.fetch('verified_builds').to_h { |b| [b.fetch('id'), b] }
checks.each do |check|
  raise 'Binary binding mismatch' unless check.fetch('binary_sha256') == builds.fetch(check.fetch('id')).fetch('cache').fetch('sha256')
  %w[stdout stderr].each do |stream|
    log = check.fetch(stream)
    next if log.fetch('truncated')
    raise 'Log digest mismatch' unless Digest::SHA256.hexdigest(log.fetch('text')) == log.fetch('sha256')
  end
  if check.fetch('outcome') == 'diagnostic_launcher_limit_failure_superseded'
    retry_id = check.fetch('check_id').sub('branch-probes/', 'mpi128-probes/')
    raise 'Unresolved startup failure' unless !check.fetch('passed') && by_check.fetch(retry_id).fetch('passed')
    raise 'Wrong startup limit' unless check.dig('command', 'selected_lines').include?('TasksMax\\=256')
    raise 'Wrong retry limit' unless by_check.fetch(retry_id).dig('command', 'selected_lines').include?('TasksMax\\=512')
    next
  end
  raise 'Recorded check did not pass' unless check.fetch('passed') && check.fetch('internal_validation') && check.dig('execution', 'success')
  next unless check.fetch('outcome') == 'winner_pass'
  benchmark = evidence.fetch('winners').find { |w| w.fetch('id') == check.fetch('id') }.fetch('cell').split('/').first
  reference = if check['reference']
    check.fetch('reference').split('/').last(2).join('/')
  else
    "probes/reference_#{benchmark}"
  end
  comparison = validate(by_check.fetch(reference).dig('stdout', 'text'), check.dig('stdout', 'text'), benchmark)
  raise "External comparison mismatch: #{check['check_id']}" unless comparison == check.fetch('comparison') && comparison.first
end
evidence.fetch('winners').each do |winner|
  raise 'Missing focused review' if winner.fetch('audit_observation').empty?
  winner.fetch('successful_checks').each { |key| raise 'Wrong check owner' unless by_check.fetch(key).fetch('id') == winner.fetch('id') }
  raise 'No successful check for winner' if winner.fetch('successful_checks').empty?
  evidence.fetch('input_helpers').each { |path, digest| raise 'Output helper changed' unless winner.fetch('files').fetch(path).fetch('sha256') == digest }
end
evidence.fetch('counterexamples').each do |counterexample|
  outputs = counterexample.fetch('outputs').map do |output|
    raise 'Counterexample failed to execute' unless output.fetch('exit_code') == '0'
    output.each_value do |value|
      next unless value.is_a?(Hash) && value.key?('sha256')
      raise 'Counterexample log digest mismatch' unless Digest::SHA256.hexdigest(value.fetch('text')) == value.fetch('sha256')
    end
    output.dig('stdout', 'text')
  end
  comparison = validate(*outputs, counterexample.fetch('benchmark'))
  raise 'Counterexample no longer reproduces' unless comparison == counterexample.fetch('comparison') && comparison.first
  raise 'Internal validator rejected counterexample' unless outputs.all? { |o| o.include?('Validation: PASSED') }
  if counterexample.fetch('benchmark') == 'spmv'
    blocks = outputs.map { |o| o.split('=== RESULTS ===')[1].split('=== END RESULTS ===')[0] }
    raise 'SpMV blocks differ' unless blocks.uniq.size == 1
  end
end
counts = { 'winners' => actual.size, 'successful_winner_checks' => checks.count { |c| c['outcome'] == 'winner_pass' },
  'successful_reference_checks' => checks.count { |c| c['outcome'] == 'reference_pass' },
  'superseded_diagnostic_launch_failures' => checks.count { |c| c['outcome'] == 'diagnostic_launcher_limit_failure_superseded' },
  'counterexamples' => evidence.fetch('counterexamples').size }
raise 'Count mismatch' unless counts == evidence.fetch('counts') && counts.values == [44, 59, 15, 11, 3]
if ARGV.include?('--sources')
  generated = ENV.fetch('WINNER_AUDIT_GENERATED', '/home/petert/llm_para_experiments')
  evidence.fetch('winners').each do |winner|
    winner.fetch('files').each do |path, pin|
      content = git(generated, 'show', "#{winner.fetch('source_commit')}:#{winner.fetch('source_path')}/#{path}")
      raise "Source mismatch #{winner['id']}/#{path}" unless Digest::SHA256.hexdigest(content) == pin.fetch('sha256')
    end
  end
end
if ARGV.include?('--coverage')
  puts "| Cell | Winner | Successful diagnostics | Observation |"
  puts "| --- | --- | ---: | --- |"
  evidence.fetch('winners').each do |w|
    puts "| #{w['cell']} | [#{w['id']}](#{w['source_url']}) | #{w['successful_checks'].size} | #{w['audit_observation']} |"
  end
else
  puts JSON.pretty_generate(counts.merge('verified' => true, 'source_blobs_checked' => ARGV.include?('--sources')))
end
