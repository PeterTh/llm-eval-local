require 'json'
require 'digest'
require 'open3'
require 'time'
require 'shellwords'
runtime = File.realpath(__dir__)
root = File.read(runtime + '/campaign.path').strip
m = JSON.parse(File.read(root + '/campaign.json'))
raise 'Already launched' if File.file?(root + '/launch.json')
m.fetch('driver_files').each { |name, hash| raise 'Driver changed' unless Digest::SHA256.file(runtime + '/' + name).hexdigest == hash }
out, status = Open3.capture2('pgrep','-u','llmtest')
raise 'Evaluation account is not idle' unless status.exitstatus == 1 && out.empty?
out, status = Open3.capture2('systemctl','--user','list-units','--type=service','--state=active,activating','--no-legend','--no-pager','llm-*')
raise "Competing services: #{out}" unless status.success? && out.strip.empty?
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock",'a')
raise 'Performance host reserved' unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
m.fetch('versions').each do |version, binary|
  proof = JSON.parse(File.read(root + '/isolation-preflight-' + version + '.json'))
  raise 'Isolation preflight differs' unless proof.values_at('version','binary_sha256','inferences_launched','lifecycle_exit_status') == [version,binary.fetch('sha256'),0,0]
end
helper = m.fetch('working_directory') + '/eval_user_support.rb'
out, err, status = Open3.capture3('su','-','llmtest','--shell=/bin/bash','-c',Shellwords.join(['ruby',helper,'claude-usage']))
raise "Quota read failed: #{err}" unless status.success? && out.start_with?('{')
quota = JSON.parse(out)
raise 'Paid extra usage must be disabled' unless quota.dig('extra_usage','is_enabled') == false
governing = quota.fetch('limits').select do |limit|
  model = limit.dig('scope','model')
  label = model.is_a?(Hash) ? (model['display_name'] || model['id']).to_s.downcase : ''
  label.empty? || label.include?('sonnet')
end
raise 'Subscription window exhausted' unless governing.all? { |limit| limit.fetch('percent').to_f < (limit['group'] == 'weekly' || %w[weekly_all weekly_scoped].include?(limit['kind']) ? 95 : 90) }
File.write(root + '/quota-before-generation.json',JSON.pretty_generate(quota)+"\n")
host_lock.close
command = ['systemd-run','--user',"--unit=#{m.fetch('generation_unit')}",
  '--description=Seven isolated Sonnet 5 historical-audit replacements', '--property=Type=exec',
  "--property=WorkingDirectory=#{m.fetch('working_directory')}",
  "--property=StandardOutput=append:#{root}/generation.log", "--property=StandardError=append:#{root}/generation.log",
  '--property=KillMode=control-group','/usr/bin/ruby',runtime+'/controller.rb']
out, err, status = Open3.capture3(*command)
raise "Launch failed: #{out} #{err}" unless status.success?
record = {'launched_at'=>Time.now.utc.iso8601,'command'=>command,'expected_replacements'=>7,
  'gpt56_replacements'=>0,'per_observation_original_cli_preserved'=>true,
  'monitoring'=>'Assistant checks the reusable first result and inspects more closely near completion; no frequent Ruby status polling or wakeup timer.'}
File.write(root + '/launch.json',JSON.pretty_generate(record)+"\n")
puts JSON.pretty_generate(record)
