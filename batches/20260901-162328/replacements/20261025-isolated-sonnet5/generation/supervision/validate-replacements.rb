require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'
require 'time'
$stdout.sync = true
$stderr.sync = true
ROOT = File.read(__dir__+'/campaign.path').strip
MANIFEST = JSON.parse(File.read(ROOT+'/campaign.json'))
EVIDENCE = ROOT+'/evaluation'
VALIDATION = '/home/petert/llm_para_local_evaluation/20261025-sonnet5-isolated-validation'
BASELINE = '/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-isolated-validation'
SOURCE = '/home/petert/llm_para_experiments'
METHOD = '/home/petert/llm_eval/experiment'
REFERENCE = '/home/petert/llm_eval/benchmarks'
BATCH = MANIFEST.fetch('campaign_id')

def checked(*args, **options)
  out, err, status = Open3.capture3(*args, **options)
  raise "#{args.first} failed: #{err}\n#{out}" unless status.success?
  out
end
def json(path, value)
  tmp=path+".#{Process.pid}.tmp"
  File.write(tmp,JSON.pretty_generate(value)+"\n")
  File.rename(tmp,path)
end
def checkpoint(state, extra={})
  value={'checked_at'=>Time.now.utc.iso8601,'state'=>state,'driver_sha256'=>Digest::SHA256.file(__FILE__).hexdigest}.merge(extra)
  json(ROOT+'/followup-progress.json',value)
  puts JSON.generate(value)
end

begin
  policy=JSON.parse(File.read(ROOT+'/followup-policy.json'))
  raise 'Follow-up driver changed' unless Digest::SHA256.file(__FILE__).hexdigest==policy.fetch('driver_sha256')
  raise 'Validation already prepared; inspect rather than overwrite' if File.exist?(EVIDENCE) || File.exist?(VALIDATION)
  checkpoint('waiting_for_generation', 'expected_replacements'=>7)
  # Wait on the controller's existing lock, with no repeated status polling.
  lock=File.open(ROOT+'/controller.lock','a')
  lock.flock(File::LOCK_EX)
  raise 'Operator stop requested' if File.file?(ROOT+'/STOP')
  raise 'Generation did not finish cleanly' unless File.file?(ROOT+'/completion.json')
  completion=JSON.parse(File.read(ROOT+'/completion.json'))
  raise 'Wrong completion scope' unless completion.values_at('replaced_observations','retained_unchanged_in_batch','gpt56_replacements') == [7,653,0]
  lock.close
  source_commit=completion.fetch('source_commit')
  method_commit=MANIFEST.fetch('source_commit')
  reference_commit=MANIFEST.fetch('sequential_source_commit')
  ids=File.readlines(ROOT+'/run-ids.txt',chomp:true)
  raise 'Wrong selection' unless ids.size==7 && ids.uniq==ids
  pids,status=Open3.capture2('pgrep','-u','llmtest')
  raise 'Evaluation account not idle' unless status.exitstatus==1 && pids.empty?
  raise 'Fable not held' unless File.file?('/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/STOP')
  raise 'MiniMax not held' unless File.file?('/home/petert/llm_para_campaigns/20261019-134120-minimax31-flash-opencode-medium/STOP')
  raise 'Source HEAD changed' unless checked('git','-C',SOURCE,'rev-parse','HEAD').strip==source_commit
  changed=checked('git','-C',SOURCE,'diff','--name-only','-z',MANIFEST.fetch('initial_generated_source_commit'),source_commit).split("\0")
  raise 'Replacement commit escaped scope' unless changed.all? { |p|p.split('/')[0]==BATCH && ids.include?(p.split('/')[1]) } && changed.map { |p|p.split('/')[1] }.uniq.sort==ids.sort
  JSON.parse(File.read(ROOT+'/unchanged-files.json')).each { |path,hash| raise "Unrelated source changed: #{path}" unless Digest::SHA256.file(SOURCE+'/'+path).hexdigest==hash }
  raise 'Uncommitted replacement outputs' unless checked('git','-C',SOURCE,'status','--porcelain','--untracked-files=no','--',BATCH).empty?
  FileUtils.mkdir_p(EVIDENCE)
  FileUtils.cp(__FILE__,EVIDENCE+'/validate-replacements.rb')
  scratch=Dir.mktmpdir('sonnet5-isolated-evaluation-20261025-','/tmp')
  checkpoint('preparing_scoped_validation','scratch_root'=>scratch)
  {'experiment'=>[METHOD,method_commit],'benchmarks'=>[REFERENCE,reference_commit],
    'generated'=>[SOURCE,source_commit],'original-backup'=>[SOURCE,source_commit]}.each do |name,(repo,revision)|
    path=scratch+'/'+name
    checked('git','clone','--shared','--no-checkout',repo,path)
    if %w[generated original-backup].include?(name)
      checked('git','-C',path,'sparse-checkout','init','--cone')
      checked('git','-C',path,'sparse-checkout','set',*ids.map { |id|BATCH+'/'+id })
    end
    checked('git','-C',path,'checkout','--detach',revision)
    raise 'Frozen checkout dirty' unless checked('git','-C',path,'status','--porcelain').empty?
  end
  require scratch+'/experiment/lib/local_evaluation'
  batches,runs=LocalEvaluation::Manifest.discover(scratch+'/generated')
  raise 'Validation scope differs' unless batches==[BATCH] && runs.keys.sort==ids.sort
  baseline=LocalEvaluation::Manifest.new(BASELINE).data
  pipeline=LocalEvaluation.pipeline_source_snapshot(scratch+'/experiment')
  raise 'Scientific pipeline changed' unless pipeline.fetch('files')==baseline.fetch('pipeline_source').fetch('files')
  benchmark_config='/home/petert/llm_para_local_evaluation/20260819-003427/benchmark_config.yaml'
  raise 'Benchmark settings changed' unless Digest::SHA256.file(benchmark_config).hexdigest=='20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970'
  plan={'created_at'=>Time.now.utc.iso8601,'batch'=>BATCH,'expected_runs'=>7,'affected_observations'=>ids,'retained_observations'=>653,
    'original_source_commit'=>source_commit,'pipeline_commit'=>method_commit,'reference_source_commit'=>reference_commit,
    'pipeline_source_sha256'=>pipeline.fetch('sha256'),'scratch_root'=>scratch,'isolated_source_checkout'=>scratch+'/generated',
    'original_source_backup'=>scratch+'/original-backup','frozen_pipeline_checkout'=>scratch+'/experiment',
    'frozen_reference_checkout'=>scratch+'/benchmarks','validation_run'=>VALIDATION,'evidence_root'=>EVIDENCE,
    'inherited_benchmark_configuration'=>benchmark_config,'scientific_execution_unchanged'=>true,
    'review_policy'=>{'primary'=>'gpt-5.6-luna/high','uncertainty_only_adjudication'=>'gpt-6.1-sol/xhigh','static_only'=>true},
    'failure_policy'=>'Preserve ordinary program failures. No reruns until pass; no hash-only scientific eligibility check.',
    'publication'=>'Replace only the seven approved Sonnet 5 records; preserve historical evidence. Leave all 17 GPT-5.6 records unchanged.'}
  FileUtils.mkdir_p(VALIDATION)
  [EVIDENCE,VALIDATION].each { |path|json(path+'/campaign.json',plan) }
  driver=scratch+'/experiment/local_evaluation.rb'
  phase=lambda do |name,*args|
    out,err,status=Open3.capture3('/usr/bin/ruby',driver,*args,chdir:scratch+'/experiment')
    File.write(EVIDENCE+'/'+name+'.log',out+err)
    raise "#{name} failed: #{err}\n#{out}" unless status.success?
    out
  end
  phase.call('validation-init','init','--run-dir='+VALIDATION,'--experiments-root='+scratch+'/generated','--benchmarks-root='+scratch+'/benchmarks')
  manifest=LocalEvaluation::Manifest.new(VALIDATION)
  %w[hostname ruby cmake cc_path cc cxx_path cxx nvcc_path nvcc mpi gpus].each do |field|
    raise "Toolchain changed: #{field}" unless manifest.data.fetch('environment').fetch(field)==baseline.fetch('environment').fetch(field)
  end
  raise 'Resource profiles changed' unless manifest.data.fetch('resource_profiles')==baseline.fetch('resource_profiles')
  phase.call('validation-preflight','preflight','--run-dir='+VALIDATION)
  dry=phase.call('validation-dry-run','validate','--run-dir='+VALIDATION,'--dry-run')
  raise 'Wrong validation dry-run selection' unless dry.include?('7 pending of 7 selected IDs')
  json(EVIDENCE+'/validation-launch-gate.json',{'checked_at'=>Time.now.utc.iso8601,'expected_runs'=>7,'source_commit'=>source_commit,
    'toolchain_match'=>true,'resource_profile_match'=>true,'measurement_pipeline_match'=>true,'pipeline_source_sha256'=>pipeline.fetch('sha256')})
  context=File.read(BASELINE+'/timing-platform-context.txt')
  old=JSON.parse(File.read(BASELINE+'/campaign.json'))
  context=context.sub(old.fetch('original_source_commit'),source_commit).sub(old.fetch('pipeline_commit'),method_commit)
  # The scientific pipeline is byte-identical; keep the existing target-platform
  # type proof and full-benchmark parameters, without inherited campaign prose.
  context=context.sub('The 2026-10-23 evaluation manifest','The 2026-10-25 evaluation manifest')
  context=context.sub(/Native validation, benchmark execution and settings are identical.*?scientific program execution\./m,
    'Native validation, benchmark execution, settings and pipeline source files are identical to the established prior evaluation. Only the seven isolated Sonnet 5 replacements are selected; validation-launch-gate.json records the comparison.')
  File.write(VALIDATION+'/timing-platform-context.txt',context)
  checkpoint('validating','validation_run'=>VALIDATION,'expected_runs'=>7)
  File.open(EVIDENCE+'/validation.log','w') do |log|
    raise 'Native validation stopped' unless system('/usr/bin/ruby',driver,'validate','--run-dir='+VALIDATION,out:log,err:log)
  end
  native=LocalEvaluation::ValidationPipeline.new(run_dir:VALIDATION)
  results=native.send(:load_results)
  raise 'Incomplete validation' unless results.keys.sort==ids.sort
  results.each { |id,result|raise "Inconsistent artifacts: #{id}" unless native.send(:validation_artifacts_intact?,id,manifest.runs.fetch(id),result) }
  raise 'Infrastructure error requires review' unless Dir[VALIDATION+'/validation/**/infrastructure_error.log'].empty?
  stages=%w[basic_para validation_build validation_run internal_validation output_comparison]
  report={'checked_at'=>Time.now.utc.iso8601,'completed'=>7,'passed'=>results.values.count(&:output_comparison),'batch'=>BATCH,
    'source_commit'=>source_commit,'manifest_sha256'=>Digest::SHA256.file(manifest.path).hexdigest,
    'validation_results_sha256'=>Digest::SHA256.file(VALIDATION+'/validation/all_validation_results.yaml').hexdigest,
    'input_revisions'=>manifest.verify_input_revisions!,
    'passing_mpi_hybrid'=>results.values.count { |r|r.output_comparison && %w[mpi hybrid].include?(r.par_type) },'passing_qtclustering'=>0,
    'failures'=>results.values.reject(&:output_comparison).map { |r|{'program_id'=>r.id_string,'failed_stage'=>stages.find { |s|!r.public_send(s) },'error'=>r.err_string} },
    'infrastructure_errors'=>[],'native_artifact_checks'=>'passed for all seven records','retained_observations_rerun'=>0,'timing_review_started'=>false}
  [EVIDENCE,VALIDATION].each { |path|json(path+'/validation-completion-review.json',report) }
  checkpoint('validation_complete_timing_review_next','passed'=>report.fetch('passed'),'completed'=>7,'evidence_root'=>EVIDENCE)
rescue Exception => error
  checkpoint('needs_review','error'=>"#{error.class}: #{error.message}")
  raise
ensure
  lock&.close unless lock&.closed?
end
