require 'json'
require 'digest'
$stdout.sync = true
$stderr.sync = true
root = File.read(__dir__ + '/campaign.path').strip
m = JSON.parse(File.read(root + '/campaign.json'))
raise 'Driver changed' unless Digest::SHA256.file(__FILE__).hexdigest == m.fetch('driver_files').fetch('run.rb')
m.fetch('files').each { |path, hash| raise "Frozen method changed: #{path}" unless Digest::SHA256.file(m.fetch('working_directory') + '/' + path).hexdigest == hash }
m.fetch('benchmark_files').each { |path, hash| raise "Sequential input changed: #{path}" unless Digest::SHA256.file(__dir__ + '/benchmarks/' + path).hexdigest == hash }
raise 'Production budget required' unless ARGV.include?('--production') && !ARGV.include?('--smoke')
raise 'Wrong source batch' unless ARGV.include?('--continue=' + m.fetch('campaign_id'))
selection = ARGV.find { |arg| arg.start_with?('--run-ids=') }&.split('=',2)&.last
raise 'Exact selection required' unless selection
ids = File.readlines(selection, chomp:true)
raise 'Unapproved selection' unless ids.size == 1 && m.fetch('observation_versions').key?(ids.first)
version = m.fetch('observation_versions').fetch(ids.first)
binary = m.fetch('versions').fetch(version)
raise 'CLI changed' unless Digest::SHA256.file(binary.fetch('path')).hexdigest == binary.fetch('sha256')
ENV['LLM_EVAL_HARNESS'] = 'claude'
ENV['LLM_EVAL_MODELS'] = 'claude-sonnet-5-cc-medium'
ENV['LLM_EVAL_CLAUDE_BINARY'] = binary.fetch('path')
Dir.chdir(m.fetch('working_directory'))
load './experiment.rb'
