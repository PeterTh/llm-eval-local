require 'json'
require 'open3'
require 'shellwords'
require 'fileutils'
require 'digest'
require 'time'
runtime = File.realpath(__dir__)
root = File.read(runtime + '/campaign.path').strip
m = JSON.parse(File.read(root + '/campaign.json'))
raise 'Preflight already recorded' if File.file?(root + '/infrastructure-preflight.json')
tests = %w[test/test_generation_filesystem.rb test/test_claude_observation_runner.rb test/test_claude_generation_observation.rb test/test_claude_usage.rb test/test_generation_cleanup.rb test/test_generation_campaign.rb test/test_experiment_selection.rb]
code = "#{tests.inspect}.each { |path| require File.expand_path(path) }"
out, status = Open3.capture2e('ruby','-Itest','-e',code,chdir:m.fetch('working_directory'))
File.write(root + '/regression-tests.log',out)
raise 'Regression failure' unless status.success? && out.include?('0 failures, 0 errors, 0 skips')
m.fetch('versions').each do |version, binary|
  command = ['ruby',m.fetch('working_directory')+'/tools/check_claude_filesystem.rb',binary.fetch('path')]
  out, err, status = Open3.capture3('su','-','llmtest','--shell=/bin/bash','-c',Shellwords.join(command))
  File.write(root+'/isolation-preflight-'+version+'.log',out+err)
  raise "Isolation failed: #{version}: #{err}" unless status.success?
  proof = JSON.parse(out.lines.last)
  raise 'Wrong preflight identity' unless proof.values_at('version','binary_sha256','inferences_launched','lifecycle_exit_status') == [version,binary.fetch('sha256'),0,0]
  File.write(root+'/isolation-preflight-'+version+'.json',JSON.pretty_generate(proof)+"\n")
end
first = File.readlines(root+'/run-ids.txt',chomp:true).first
File.write(root+'/dry-run-ids.txt',first+"\n")
out, status = Open3.capture2e('ruby',runtime+'/run.rb','--production','--continue='+m.fetch('campaign_id'),'--run-ids='+root+'/dry-run-ids.txt')
File.write(root+'/preflight-dry-run.txt',out)
raise 'Dry-run mismatch' unless status.success? && out.include?('Total number of experiments to run: 1') && out.include?('--model claude-sonnet-5 --effort medium') && out.include?('Per-run wall clock limit: 240 minutes')
record = {'checked_at'=>Time.now.utc.iso8601,'status'=>'passed','inferences_launched'=>0,
  'regression_summary'=>File.readlines(root+'/regression-tests.log').find { |line| line.include?(' assertions, ') }&.strip,
  'versions'=>m.fetch('versions').keys,'first_reusable_replacement'=>first,'originals_untouched'=>true,
  'preflight_script_sha256'=>Digest::SHA256.file(__FILE__).hexdigest}
FileUtils.cp(__FILE__,root+'/preflight.rb')
File.write(root+'/infrastructure-preflight.json',JSON.pretty_generate(record)+"\n")
puts JSON.pretty_generate(record)
