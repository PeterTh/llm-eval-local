require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'time'
require 'socket'
require '/home/petert/llm_eval/experiment/lib/experiment_selection'

def checked(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{err}\n#{out}" unless status.success?
  out
end
def sha(path); Digest::SHA256.file(path).hexdigest; end
def write_json(path, value); File.write(path, JSON.pretty_generate(value) + "\n"); end
def archive(repo, dest)
  FileUtils.mkdir_p(dest)
  raise 'Archive failed' unless Open3.pipeline(['git', '-C', repo, 'archive', 'HEAD'], ['tar', '-xf', '-', '-C', dest]).all?(&:success?)
end
def hashes(root)
  Dir[File.join(root, '**', '*')].select { |p| File.file?(p) }.sort.to_h { |p| [p.delete_prefix(root + '/'), sha(p)] }
end

runtime = File.realpath(__dir__)
raise 'Already prepared' if File.exist?(runtime + '/campaign.path')
repo = '/home/petert/llm_eval/experiment'
bench_repo = '/home/petert/llm_eval/benchmarks'
source_repo = '/home/petert/llm_para_experiments'
audit_root = '/home/petert/llm_generation_access_audits/20261025-historical'
audit = JSON.parse(File.read(audit_root + '/review.json'))
findings = audit.fetch('findings').select { |f| f.fetch('id').include?('_claude-sonnet-5-cc-medium_') }
raise 'Wrong approved scope' unless findings.size == 7 && findings.map { |f| f['batch'] }.uniq == ['20260901-162328']
batch = '20260901-162328'
results = source_repo + '/' + batch
benchmarks = %w[black-scholes cahn-hilliard cholesky floydwarshall matmul nbody qtclustering roomsim spmv stencil3d unstructured]
ids = ExperimentSelection.configurations(benchmarks: benchmarks, models: ['claude-sonnet-5-cc-medium'], backends: %w[omp cuda mpi hybrid], repetitions: 5).map { |c| ExperimentSelection.id(c) }.select { |id| findings.any? { |f| f['id'] == id } }
raise 'Unrelated staged changes' unless checked('git', '-C', source_repo, 'diff', '--cached', '--name-only').empty?
raise 'Original batch is dirty' unless checked('git', '-C', source_repo, 'status', '--porcelain', '--', batch).empty?
raise 'Benchmark worktree dirty' unless checked('git', '-C', bench_repo, 'status', '--porcelain').empty?
raise 'Unexpected generated-source branch' unless checked('git', '-C', source_repo, 'branch', '--show-current').strip == 'claude'
raise 'Fable is not suspended' unless File.file?('/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/STOP')
raise 'MiniMax is not held' unless File.file?('/home/petert/llm_para_campaigns/20261019-134120-minimax31-flash-opencode-medium/STOP')

originals = ids.to_h do |id|
  finding = findings.find { |f| f['id'] == id }
  transcript = results + '/' + id + '/output.txt'
  raise "Audited transcript changed: #{id}" unless sha(transcript) == finding.fetch('transcript_sha256')
  events = File.foreach(transcript).filter_map { |line| JSON.parse(line) rescue nil }
  init = events.find { |e| e['type'] == 'system' && e['subtype'] == 'init' }
  raise 'Original model differs' unless init.fetch('model') == 'claude-sonnet-5'
  [id, { 'version' => init.fetch('claude_code_version'), 'tools' => init.fetch('tools').sort,
    'plugins' => init.fetch('plugins', []), 'instruction' => File.read(results + '/' + id + '/instruction.txt'),
    'transcript_sha256' => sha(transcript), 'category' => finding.fetch('category') }]
end
raise 'Original version scope changed' unless originals.values.group_by { |o| o['version'] }.transform_values(&:size) == {'2.1.252'=>5, '2.1.269'=>2}
versions = originals.values.map { |o| o['version'] }.uniq.to_h do |version|
  path = '/home/llmtest/.local/share/claude/versions/' + version
  manifest = JSON.parse(File.read(runtime + '/claude-' + version + '-manifest.json'))
  expected = manifest.fetch('platforms').fetch('linux-x64')
  raise 'Official binary checksum differs' unless sha(path) == expected.fetch('checksum') && File.size(path) == expected.fetch('size')
  [version, {'path'=>path, 'sha256'=>sha(path), 'official_manifest_sha256'=>sha(runtime + '/claude-' + version + '-manifest.json')}]
end

stamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
campaign = '/home/petert/llm_para_campaigns/' + stamp + '-sonnet5-isolated-replacements'
raise 'Campaign destination exists' if File.exist?(campaign)
FileUtils.mkdir_p(campaign, mode:0700)
archive(repo, runtime + '/experiment')
archive(bench_repo, runtime + '/benchmarks')
FileUtils.cp_r(runtime + '/experiment', campaign + '/method')
FileUtils.cp_r(runtime + '/benchmarks', campaign + '/sequential-input')

# Prove task text and Claude flags have not drifted from the retained originals.
current = File.read(runtime + '/experiment/experiment.rb')
historical = checked('git', '-C', repo, 'show', 'fa04613:experiment.rb')
flag_block = /CLAUDE_DISALLOWED_TOOLS =.*?(?=INSTRUCTION_START)/m
historical_flags = historical[flag_block]
compatible_flags = historical_flags.sub('WebSearch WebFetch Task Workflow', 'WebSearch WebFetch Agent Task Workflow')
raise 'Claude flags/environment changed beyond the additional Agent alias' unless current[flag_block] == compatible_flags
prompt_scope = Module.new
%w[OMP CUDA MPI HYBRID].each { |name| prompt_scope.const_set('PAR_' + name, name.downcase) }
prompt_scope.module_eval(current[/INSTRUCTION_START =.*?(?=EVAL_USER)/m])
prompt_scope.module_eval(current[/^def build_instruction\(.*?^end/m])
prompt_builder = Object.new.extend(prompt_scope)
ids.each do |id|
  benchmark, _, backend, = id.split('_')
  raise "Task prompt differs: #{id}" unless prompt_builder.build_instruction(benchmark, backend) == originals.fetch(id).fetch('instruction')
end

tracked = checked('git', '-C', source_repo, 'ls-files', '-z', '--', batch).split("\0")
superseded, unchanged = tracked.partition { |path| ids.include?(path.split('/')[1]) }
raise 'Wrong retained batch count' unless tracked.map { |path| path.split('/')[1] }.uniq.size == 660
write_json(campaign + '/superseded-files.json', superseded.to_h { |path| [path, sha(source_repo + '/' + path)] })
write_json(campaign + '/unchanged-files.json', unchanged.to_h { |path| [path, sha(source_repo + '/' + path)] })
write_json(campaign + '/audited-findings.json', findings)
write_json(campaign + '/original-observations.json', originals)
File.write(campaign + '/run-ids.txt', ids.join("\n") + "\n")
FileUtils.mkdir_p(campaign + '/release-verification')
%w[claude-2.1.252-manifest.json claude-2.1.252-manifest.json.sig claude-2.1.269-manifest.json claude-code.asc].each do |name|
  FileUtils.cp(runtime + '/' + name, campaign + '/release-verification/' + name)
end
signature = checked('gpg', '--homedir', runtime + '/gnupg', '--batch', '--status-fd', '1', '--verify', runtime + '/claude-2.1.252-manifest.json.sig', runtime + '/claude-2.1.252-manifest.json')
raise 'Unexpected signing identity' unless signature.include?('VALIDSIG 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE ')
File.write(campaign + '/release-verification/signature-check.txt', signature)
%w[prepare.rb run.rb controller.rb launch.rb].each { |name| FileUtils.cp(runtime + '/' + name, campaign + '/' + name) }
manifest = {
  'schema_version'=>1, 'prepared_at'=>Time.now.utc.iso8601, 'host'=>Socket.gethostname,
  'campaign_id'=>batch, 'replacement_campaign_id'=>stamp, 'label'=>'Sonnet 5 medium isolated replacements',
  'harness'=>'claude', 'invoked_model'=>'claude-sonnet-5', 'reasoning_effort'=>'medium',
  'claude_version'=>originals.fetch(ids.first).fetch('version'), 'versions'=>versions,
  'observation_versions'=>originals.transform_values { |o| o.fetch('version') },
  'expected_runs'=>ids.size, 'preflight_ids'=>[ids.first], 'per_run_timeout_seconds'=>14400,
  'generation_filesystem_policy'=>'observation-mount-allowlist-v1',
  'source_branch'=>'claude', 'initial_generated_source_commit'=>checked('git','-C',source_repo,'rev-parse','HEAD').strip,
  'source_commit'=>checked('git','-C',repo,'rev-parse','HEAD').strip,
  'sequential_source_commit'=>checked('git','-C',bench_repo,'rev-parse','HEAD').strip,
  'runtime_root'=>runtime, 'working_directory'=>runtime+'/experiment', 'persistent_results'=>results,
  'files'=>hashes(runtime+'/experiment'), 'benchmark_files'=>hashes(runtime+'/benchmarks'),
  'driver_files'=>%w[prepare.rb run.rb controller.rb launch.rb].to_h { |name| [name,sha(runtime+'/'+name)] },
  'audit_path'=>audit_root, 'audit_sha256'=>sha(audit_root+'/review.json'),
  'generation_unit'=>"llm-sonnet5-replacements-#{stamp}.service",
  'backup_root'=>runtime+'/superseded',
  'retained_unchanged_in_batch'=>653, 'excluded_gpt56_ids'=>audit.fetch('findings').reject { |f| ids.include?(f['id']) }.map { |f| f['id'] },
  'user_authorization'=>'Replace the seven audited Sonnet 5 observations only; leave the 17 GPT-5.6 cases untouched.',
  'policy'=>'One accepted fresh generation per affected ID irrespective of program correctness, using the original per-ID CLI/model/effort/prompt/budget with repaired filesystem isolation. Native provider retry conventions remain unchanged. Preserve originals in git and local recoverable backup.',
  'preflight'=>'No-inference isolation checks for both pinned CLIs; first actual replacement doubles as reusable availability/metadata preflight. Stop on model or harness mismatch, never silently substitute.',
  'restriction_compatibility'=>'The current wrapper additionally disallows the newer Agent alias alongside the original Task name. All other Claude flags/environment are byte-identical to the historical configuration; every replacement must expose exactly the original recorded tool/plugin set.',
  'next_stages'=>'Original-source retention commit, scoped validation, Luna timing review with Sol 6.1 only for ambiguity, timing-only correction and revalidation where needed, established-size benchmarking, scoped integration.'
}
write_json(campaign + '/campaign.json', manifest)
File.write(runtime + '/campaign.path', campaign + "\n")
File.write(campaign + '/campaign.path', campaign + "\n")
puts JSON.pretty_generate(manifest.slice('replacement_campaign_id','expected_runs','observation_versions','generation_unit'))
puts campaign
