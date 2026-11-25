# frozen_string_literal: true
require 'json'
require 'open3'
require 'fileutils'
require 'digest'
require 'time'

scratch = __dir__
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
original = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3'
successor = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v4'
old_pipeline = File.join(scratch, 'observer-pipeline-v3')
new_pipeline = File.join(scratch, 'observer-pipeline-v4')
evidence = File.join(campaign, 'observer-helper-resume')
raise 'Resume already prepared' if File.exist?(successor) || File.exist?(evidence)
out, status = Open3.capture2('pgrep', '-u', 'llmtest')
raise 'Generation account active' unless status.exitstatus == 1 && out.empty?
state, status = Open3.capture2('systemctl', '--user', 'show', 'llm-gpt62-medium-validation-20261125.service', '--property=ActiveState', '--value')
raise 'Validation still active' if %w[active activating reloading].include?(state.strip)
old_review = <<~'RUBY'
  require File.join(ARGV.fetch(0), 'lib/local_evaluation')
  root = ARGV.fetch(1)
  manifest = LocalEvaluation::Manifest.new(root)
  manifest.verify_input_revisions!
  pipeline = LocalEvaluation::ValidationPipeline.new(run_dir: root)
  results = pipeline.send(:load_results)
  results.each do |id, result|
    raise "Inconsistent prior artifacts: #{id}" unless pipeline.send(:validation_artifacts_intact?, id, manifest.runs.fetch(id), result)
  end
  puts JSON.generate('ids' => results.keys.sort, 'passed' => results.values.count(&:output_comparison),
    'manifest_sha256' => LocalEvaluation.sha256_file(manifest.path),
    'results_sha256' => LocalEvaluation.sha256_file(File.join(root, 'validation/all_validation_results.yaml')))
RUBY
stdout, stderr, status = Open3.capture3('/usr/bin/ruby', '-e', old_review, old_pipeline, original)
raise "Prior immutable validation failed: #{stdout} #{stderr}" unless status.success?
old_check = JSON.parse(stdout)
raise 'Prior completed set differs' unless old_check.fetch('ids').size == 32 && old_check.fetch('passed') == 32
require File.join(new_pipeline, 'lib/local_evaluation')
run_lock = LocalEvaluation::RunLock.new(original)
host_lock = LocalEvaluation::HostPerformanceLock.new
begin
  before = LocalEvaluation::Manifest.new(original)
  after = LocalEvaluation::Manifest.create(experiments_root: before.data.fetch('experiments_root'),
    run_dir: successor, benchmarks_root: before.benchmarks_root)
  %w[experiments_root benchmarks_root experiment_repository benchmark_repository environment resource_profiles batches run_count runs].each do |key|
    raise "Unexpected input change: #{key}" unless before.data.fetch(key) == after.data.fetch(key)
  end
  changed = (before.data.fetch('pipeline_source').fetch('files').keys | after.data.fetch('pipeline_source').fetch('files').keys).select do |name|
    before.data.fetch('pipeline_source').fetch('files')[name] != after.data.fetch('pipeline_source').fetch('files')[name]
  end.sort
  expected = %w[tools/validation_audit/full_array_adapters.rb tools/validation_audit/full_array_observer.py tools/validation_audit/native_full_array_validation.rb]
  raise "Unexpected pipeline change: #{changed}" unless changed == expected
  raise 'Wrong frozen pipeline revision' unless after.data.dig('script_repository', 'commit') == '8a2488cd27ffc7a79f30dca1d77fe0a356ee64fd' &&
    !after.data.dig('script_repository', 'dirty')
  after.verify_input_revisions!
  FileUtils.mkdir_p(evidence)
  FileUtils.cp(__FILE__, File.join(evidence, File.basename(__FILE__)))
  FileUtils.cp(File.join(scratch, 'pilot-result-helper-coverage.rb'), evidence)
  pilot_path = File.join(scratch, 'result-helper-coverage-pilot/pilot.json')
  pilot = JSON.parse(File.read(pilot_path))
  raise 'Pilot did not pass with the frozen method' unless pilot.fetch('observations').size == 9 && pilot.fetch('observations').all? { |row| row.dig('result', 'passed') } &&
    pilot.fetch('method_sha256') == ValidationAudit::NativeFullArray.methods
  FileUtils.cp(pilot_path, evidence)
  tests = File.read(File.join(scratch, 'observer-helper-host-regression-tests.log'))
  raise 'Regression gate missing' unless tests.include?('532 runs, 3207 assertions, 0 failures, 0 errors, 0 skips')
  FileUtils.cp(File.join(scratch, 'observer-helper-host-regression-tests.log'), evidence)
  FileUtils.cp(File.join(scratch, 'observer-helper-resume-template.json'), evidence)
  FileUtils.cp_r(File.join(scratch, 'result-helper-coverage-pilot'), File.join(evidence, 'pilot'))
  %w[campaign.json validation-progress.json validation-driver.rb local-evaluation-driver.rb verify-validation-completion.rb].each do |name|
    path = File.join(campaign, name)
    FileUtils.cp(path, File.join(evidence, 'initial-' + name)) if File.file?(path)
  end
  directory_hashes = lambda do |directory|
    Dir[File.join(directory, '**/*')].select { |path| File.file?(path) }.sort.to_h do |path|
      raise "Symlink in retained validation: #{path}" if File.symlink?(path)
      [path.delete_prefix(directory + '/'), LocalEvaluation.sha256_file(path)]
    end
  end
  FileUtils.mkdir_p(File.join(successor, 'validation'))
  FileUtils.cp_r(File.join(original, 'validation/reference'), File.join(successor, 'validation/reference'), preserve: true)
  receipts = old_check.fetch('ids').map do |id|
    source = File.join(original, 'validation', id)
    target = File.join(successor, 'validation', id)
    hashes = directory_hashes.call(source)
    FileUtils.cp_r(source, target, preserve: true)
    raise "Copied artifacts changed: #{id}" unless directory_hashes.call(target) == hashes
    path = File.join(target, 'validation_metadata.yaml')
    metadata = LocalEvaluation.load_yaml(path)
    raise 'Prior manifest binding differs' unless metadata.fetch('manifest_sha256') == old_check.fetch('manifest_sha256')
    metadata['manifest_sha256'] = LocalEvaluation.sha256_file(after.path)
    metadata['imported_validation'] = { 'run_dir' => original,
      'manifest_sha256' => old_check.fetch('manifest_sha256'),
      'metadata_sha256' => hashes.fetch('validation_metadata.yaml'),
      'reason' => 'Rebind the manifest only; reuse an unaffected complete validation after a binary-scoped observer addition. Original method receipts and all scientific evidence remain byte-identical.' }
    LocalEvaluation.atomic_yaml(path, metadata)
    new_hashes = directory_hashes.call(target)
    raise "Scientific evidence changed: #{id}" unless new_hashes.reject { |name, _| name == 'validation_metadata.yaml' } == hashes.reject { |name, _| name == 'validation_metadata.yaml' }
    { 'id' => id, 'original_artifacts_sha256' => hashes,
      'rebound_metadata_sha256' => new_hashes.fetch('validation_metadata.yaml') }
  end
  FileUtils.cp(File.join(original, 'validation/all_validation_results.yaml'), File.join(successor, 'validation/all_validation_results.yaml'), preserve: true)
  pipeline = LocalEvaluation::ValidationPipeline.new(run_dir: successor)
  results = pipeline.send(:load_results)
  raise 'Imported result set changed' unless results.keys.sort == old_check.fetch('ids')
  results.each do |id, result|
    raise "Imported validation no longer intact: #{id}" unless pipeline.send(:validation_artifacts_intact?, id, after.runs.fetch(id), result)
  end
  raise 'Prior manifest changed' unless LocalEvaluation.sha256_file(before.path) == old_check.fetch('manifest_sha256')
  raise 'Prior results changed' unless LocalEvaluation.sha256_file(File.join(original, 'validation/all_validation_results.yaml')) == old_check.fetch('results_sha256')
  receipts.each do |record|
    raise 'Prior artifacts changed' unless directory_hashes.call(File.join(original, 'validation', record.fetch('id'))) == record.fetch('original_artifacts_sha256')
  end
  report = { 'created_at' => Time.now.utc.iso8601, 'initial_run' => original, 'successor_run' => successor,
    'source_commit' => after.data.dig('experiment_repository', 'commit'),
    'initial_pipeline' => before.data.fetch('pipeline_source'), 'successor_pipeline' => after.data.fetch('pipeline_source'),
    'initial_validation_review' => old_check, 'successor_manifest_sha256' => LocalEvaluation.sha256_file(after.path),
    'changed_method_files' => changed, 'imported_complete_records' => receipts, 'pending_records' => 408,
    'program_source_changes' => 0, 'benchmark_runs' => 0,
    'policy' => 'Preserve the initial immutable manifest and all original scientific evidence; import completed unaffected records with explicit original-manifest and metadata bindings. Only pending validation continues.' }
  LocalEvaluation.atomic_write(File.join(evidence, 'resume.json'), JSON.pretty_generate(report) + "\n")
  config = JSON.parse(File.read(File.join(campaign, 'campaign.json')))
  config['observer_resume_history'] = Array(config['observer_resume_history']) + [File.join(evidence, 'resume.json')]
  config.merge!('previous_validation_run' => original, 'validation_run' => successor,
    'pipeline_commit' => after.data.dig('script_repository', 'commit'),
    'pipeline_source_sha256' => after.data.dig('pipeline_source', 'sha256'),
    'frozen_pipeline_checkout' => new_pipeline,
    'validation_resume_command' => "ruby #{scratch}/local-evaluation-driver.rb validate --run-dir=#{successor}",
    'observer_resume_evidence' => File.join(evidence, 'resume.json'))
  [campaign, successor].each { |dir| LocalEvaluation.atomic_write(File.join(dir, 'campaign.json'), JSON.pretty_generate(config) + "\n") }
  # Mechanical template rebinding. Original driver bytes remain in the campaign.
  %w[local-evaluation-driver.rb validation-driver.rb verify-validation-completion.rb].each do |name|
    path = File.join(scratch, name)
    bytes = File.binread(path).gsub(old_pipeline, new_pipeline).gsub(original, successor)
    LocalEvaluation.atomic_write(path, bytes)
    FileUtils.cp(path, File.join(campaign, name))
  end
  archive = File.join(scratch, 'observer-method.tar')
  raise 'Could not archive observer method' unless system('git', '-C', new_pipeline, 'archive', "--output=#{archive}", 'HEAD')
  FileUtils.mkdir_p(File.join(evidence, 'method'))
  raise 'Could not retain observer method' unless system('tar', '-xf', archive, '-C', File.join(evidence, 'method'))
  puts JSON.pretty_generate(report.slice('initial_run', 'successor_run', 'pending_records', 'changed_method_files').merge('imported_records' => receipts.size))
ensure
  host_lock.close
  run_lock.close
end
