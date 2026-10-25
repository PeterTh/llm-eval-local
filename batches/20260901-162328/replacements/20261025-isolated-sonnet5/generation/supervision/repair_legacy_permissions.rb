require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'time'
root = File.read(__dir__+'/campaign.path').strip
m = JSON.parse(File.read(root+'/campaign.json'))
raise 'Repair already recorded' if File.exist?(root+'/legacy-permission-repair.json')
pids, status = Open3.capture2('pgrep','-u','llmtest')
raise 'Evaluation account not idle' unless status.exitstatus==1 && pids.empty?
state, status = Open3.capture2('systemctl','--user','show',m.fetch('generation_unit'),'--property=ActiveState','--value')
raise 'Controller still active' unless status.success? && %w[failed inactive].include?(state.strip)
original = JSON.parse(File.read(root+'/superseded-files.json'))
reports = Dir[root+'/observations/*.json'].to_h { |p| [File.basename(p),Digest::SHA256.file(p).hexdigest] }
raise 'Unexpected completed scope' unless reports.keys == ['black-scholes_claude-sonnet-5-cc-medium_mpi_r2.json']
actions=[]
m.fetch('observation_versions').each_key do |id|
  next if reports.key?(id+'.json')
  target = m.fetch('persistent_results')+'/'+id
  raise 'Unsafe original path' unless File.directory?(target) && File.realpath(target)==target
  backup = m.fetch('backup_root')+'/'+id
  expected = original.select { |path,_| path.split('/')[1]==id }
  evidence_root = File.directory?(backup) ? backup : target
  expected.each do |path, hash|
    relative = path.split('/')[2..].join('/')
    raise 'Original not safely retained' unless Digest::SHA256.file(evidence_root+'/'+relative).hexdigest==hash
    if File.file?(target+'/'+relative)
      raise 'Canonical source changed unexpectedly' unless Digest::SHA256.file(target+'/'+relative).hexdigest==hash
    end
  end
  directories = Dir[target+'/**/*'].select { |path| File.lstat(path).directory? && !File.writable?(path) }
  raise 'Symlinked directory scope' unless directories.all? { |path| File.realpath(path)==path && path.start_with?(target+'/') }
  unless directories.empty?
    relatives = directories.map { |path| path.delete_prefix(target+'/') }
    command = Shellwords.join(['/usr/bin/chmod','a+rwx','--',*relatives])
    out, err, status = Open3.capture3('su','llmtest','--shell=/bin/bash','-c',command,chdir:target)
    raise "Legacy ownership cleanup failed: #{out} #{err}" unless status.success?
    raise 'Directory remains unwritable' unless directories.all? { |path| File.writable?(path) }
  end
  removed_redundant_copy = false
  if File.directory?(backup)
    # A prior cross-filesystem move copied the complete observation, then failed
    # removing owner-only build directories. Delete only that verified duplicate.
    FileUtils.remove_entry_secure(target)
    removed_redundant_copy = true
  end
  actions << {'id'=>id,'directories_made_removable'=>directories.map { |p|p.delete_prefix(target+'/') },
    'redundant_partial_original_removed'=>removed_redundant_copy,'recovery'=>File.directory?(backup) ? backup : 'Original remains canonical until its own replacement begins'}
end
reports.each { |name,hash| raise 'Completed replacement changed' unless Digest::SHA256.file(root+'/observations/'+name).hexdigest==hash }
record = {'recorded_at'=>Time.now.utc.iso8601,'reason'=>'Cross-filesystem move encountered old NFS anonymous-owner build directories; generated content is unaffected.',
  'completed_replacement_reports_sha256'=>reports,'actions'=>actions,'generations_repeated'=>0,'source_content_edited'=>false,
  'original_git_commit'=>m.fetch('initial_generated_source_commit'),'script_sha256'=>Digest::SHA256.file(__FILE__).hexdigest}
FileUtils.cp(__FILE__,root+'/repair_legacy_permissions.rb')
File.write(root+'/legacy-permission-repair.json',JSON.pretty_generate(record)+"\n")
puts JSON.pretty_generate(record)
