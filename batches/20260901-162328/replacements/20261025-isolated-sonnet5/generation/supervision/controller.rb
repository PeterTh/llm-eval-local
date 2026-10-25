require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'time'
$stdout.sync = true
$stderr.sync = true
root = File.read(__dir__ + '/campaign.path').strip
manifest = JSON.parse(File.read(root + '/campaign.json'))
manifest.fetch('driver_files').each { |name, hash| raise "Driver changed: #{name}" unless Digest::SHA256.file(__dir__ + '/' + name).hexdigest == hash }
require File.join(manifest.fetch('working_directory'), 'tools/generation_campaign')

class SonnetReplacementCampaign < GenerationCampaign
  def observation(id, baseline: nil)
    @manifest['claude_version'] = @manifest.fetch('observation_versions').fetch(id)
    super
  end
  def originals; @originals ||= JSON.parse(File.read(@root + '/original-observations.json')); end
  def verify_unchanged!
    @unchanged ||= JSON.parse(File.read(@root + '/unchanged-files.json'))
    @unchanged.each { |path, hash| raise "Unrelated original changed: #{path}" unless Digest::SHA256.file(File.dirname(@results) + '/' + path).hexdigest == hash }
    raise 'Fable STOP removed' unless File.file?('/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/STOP')
    raise 'MiniMax STOP removed' unless File.file?('/home/petert/llm_para_campaigns/20261019-134120-minimax31-flash-opencode-medium/STOP')
  end
  def preserve_original!(id)
    backup = @manifest.fetch('backup_root') + '/' + id
    if File.directory?(backup)
      expected = JSON.parse(File.read(@root + '/superseded-files.json')).select { |path,_| path.split('/')[1] == id }
      expected.each { |path, hash| raise 'Superseded backup changed' unless Digest::SHA256.file(backup + '/' + path.split('/')[2..].join('/')).hexdigest == hash }
      return
    end
    raise 'Incomplete earlier replacement needs review' if File.file?(@observations + '/' + id + '.json')
    path = @results + '/' + id
    raise 'Original transcript changed' unless Digest::SHA256.file(path + '/output.txt').hexdigest == originals.fetch(id).fetch('transcript_sha256')
    FileUtils.mkdir_p(@manifest.fetch('backup_root'), mode:0700)
    FileUtils.mv(path, backup)
  end
  def commit_replacements!
    raise 'Wrong branch' unless git('branch','--show-current').strip == @manifest.fetch('source_branch')
    raise 'Source HEAD changed' unless git('rev-parse','HEAD').strip == @manifest.fetch('initial_generated_source_commit')
    raise 'Unrelated staged changes' unless git('diff','--cached','--name-only').empty?
    paths = @ids.map { |id| @batch + '/' + id }
    @ids.each { |id| raise 'Nested generated repository' unless Dir.glob(@results + '/' + id + '/**/.git', File::FNM_DOTMATCH).empty? }
    git('add','--',*paths)
    changed = git('diff','--cached','--name-only','-z').split("\0")
    raise 'Unexpected staged scope' unless !changed.empty? && changed.all? { |path| path.split('/')[0] == @batch && @ids.include?(path.split('/')[1]) }
    entries = git('ls-files','--stage','--',*paths).lines
    raise 'Nonregular source entry' unless entries.all? { |line| line.start_with?('100644 ','100755 ') }
    tracked = git('ls-files','-z','--',*paths).split("\0")
    @ids.each do |id|
      %w[output.txt timing.txt instruction.txt usage.txt process-status.txt claude-filesystem.txt].each do |name|
        raise "Required metadata ignored: #{id}/#{name}" unless tracked.include?(@batch+'/'+id+'/'+name)
      end
    end
    changed.each do |relative|
      path = File.dirname(@results) + '/' + relative
      next unless File.file?(path)
      raise 'Build artifact staged' if relative.match?(%r{/(?:build[^/]*|CMakeFiles|node_modules|\.git)/}) || File.binread(path,4) == "\x7fELF"
    end
    git('commit','--quiet','-m','Replace seven Sonnet 5 observations after historical access audit')
    json('completion.json', {'completed_at'=>Time.now.utc.iso8601, 'source_commit'=>git('rev-parse','HEAD').strip,
      'source_batch'=>@batch, 'replaced_observations'=>7, 'retained_unchanged_in_batch'=>653,
      'gpt56_replacements'=>0, 'next_stage'=>'Scoped validation, static timing review, established-size benchmarking.'})
  end
  def run_replacements
    raise 'Already complete; do not regenerate' if File.file?(@root + '/completion.json')
    lock = File.open(@root + '/controller.lock','a')
    raise 'Controller already active' unless lock.flock(File::LOCK_EX | File::LOCK_NB)
    host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock",'a')
    raise 'Native performance workload already active' unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
    verify_unchanged!
    @ids.each do |id|
      check_stop!
      ensure_account_idle!
      preserve_original!(id)
      expected = originals.fetch(id)
      baseline = expected.slice('tools','plugins')
      execute_observation(id, baseline:baseline, phase:'isolated_replacements')
      report = observation(id, baseline:baseline)
      raise 'Replacement lacks isolation' unless report.dig('filesystem_isolation','policy') == @manifest.fetch('generation_filesystem_policy')
      raise 'Task prompt changed' unless File.read(@results+'/'+id+'/instruction.txt') == expected.fetch('instruction')
      gate = @root + '/preflight-review.json'
      unless File.exist?(gate)
        json('preflight-review.json', {'accepted'=>true, 'id'=>id, 'report'=>report,
          'criterion'=>'Original model/version/tools/prompt/budget and isolated filesystem; program correctness is not an admission criterion.'})
        puts "Reusable first replacement accepted: #{id}"
      end
      verify_unchanged!
    end
    ensure_account_idle!
    verify_unchanged!
    snapshot('retaining_replacements')
    commit_replacements!
    snapshot('complete')
  rescue Exception => error
    snapshot('needs_review', error:"#{error.class}: #{error.message}")
    raise
  ensure
    host_lock&.close
    lock&.close
  end
end

SonnetReplacementCampaign.new(root).run_replacements
