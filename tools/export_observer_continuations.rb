# frozen_string_literal: true
require_relative 'artifact_common'
require 'open3'
require 'time'

# Retain observer compatibility/continuation evidence without copying binaries,
# captured arrays, builds, or repeated copies of the evaluation method.
module ObserverContinuationsExport
  module_function

  def run(root:, evaluation:, batch_id:, resume: false)
    raise 'Unsafe batch' unless batch_id.match?(/\A\d{8}-\d{6}\z/)
    destination = "batches/#{batch_id}/provenance/observer-continuations"
    if File.exist?(File.join(root, destination))
      raise 'Continuation evidence already exported' unless resume && !File.exist?(File.join(root, destination, 'index.json'))
    end
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |path|
      relative = LocalEvalArtifact.relative_path(root, path)
      next unless relative.start_with?('pipeline/', 'method/') || relative.match?(%r{\Abatches/[^/]+/(?:method|generation/(?:method|runtime-method)|timing-corrections/method|benchmark/method)/})
      reusable[LocalEvalArtifact.sha256(path)] ||= relative
    end
    retained = {}
    retain = lambda do |source, relative|
      raise "Not regular evidence: #{source}" unless File.file?(source) && !File.symlink?(source)
      digest = LocalEvalArtifact.sha256(source)
      stored = retained[digest] || reusable[digest]
      unless stored
        stored = File.join(destination, relative)
        target = File.join(root, stored)
        FileUtils.mkdir_p(File.dirname(target))
        if File.exist?(target)
          raise 'Partial export differs' unless resume && !File.symlink?(target) && LocalEvalArtifact.sha256(target) == digest
        else
          FileUtils.cp(source, target)
        end
        retained[digest] = stored
      end
      { 'path' => stored, 'sha256' => digest }
    end
    phases = %w[observer-resume observer-rebuild-resume observer-helper-resume observer-root-stream-resume]
    methods = {}
    receipts = phases.to_h do |phase|
      directory = File.join(evaluation, phase)
      receipt = JSON.parse(File.read(File.join(directory, 'resume.json')))
      %w[initial_pipeline successor_pipeline].each do |key|
        pipeline = receipt.fetch(key)
        signature = pipeline.fetch('sha256')
        next if methods.key?(signature)
        source_root = pipeline.fetch('root')
        commit, error, status = Open3.capture3('git', '-C', source_root, 'rev-parse', 'HEAD')
        raise "Cannot bind method: #{error}" unless status.success?
        layout = pipeline.fetch('files').to_h do |name, digest|
          raise 'Unsafe method name' if name.start_with?('/') || name.split('/').any? { |p| ['', '.', '..'].include?(p) }
          source = File.join(source_root, name)
          raise "Continuation method changed: #{name}" unless LocalEvalArtifact.sha256(source) == digest
          [name, retain.call(source, "method/#{signature}/#{name}")]
        end
        methods[signature] = { 'commit' => commit.strip, 'files' => layout }
      end
      files = {}
      Dir[File.join(directory, '**', '*')].sort.each do |source|
        next unless File.file?(source)
        relative = source.delete_prefix(directory + '/')
        # Root-level operational receipts/scripts plus compact nested observer
        # descriptions and exact validation output; never numerical array dumps.
        allowed = if !relative.include?('/')
          %w[.json .rb .txt .log].include?(File.extname(source))
        else
          %w[.json .yaml .yml].include?(File.extname(source)) ||
            relative.match?(/_(?:stdout|stderr|command|exitcode|wall_time)\.log\z/)
        end
        next unless allowed
        files[relative] = retain.call(source, "#{phase}/#{relative}")
      end
      [phase, { 'receipt' => files.fetch('resume.json'), 'files' => files }]
    end
    index = { 'schema_version' => 1, 'batch' => batch_id, 'exported_at' => Time.now.utc.iso8601,
      'purpose' => 'Observer ABI/output-layout compatibility continuations. Completed scientific records were reused; no performance measurements were repeated.',
      'phases' => receipts, 'method_layouts' => methods,
      'unique_new_files' => retained.size,
      'unique_new_bytes' => retained.values.sum { |relative| File.size(File.join(root, relative)) },
      'generated_source_copies' => 0, 'binaries' => 0, 'captured_array_dumps' => 0,
      'exporter_sha256' => LocalEvalArtifact.sha256(__FILE__) }
    path = File.join(root, destination, 'index.json')
    File.write(path, JSON.pretty_generate(index) + "\n")
    puts JSON.pretty_generate(index.slice('batch', 'unique_new_files', 'unique_new_bytes', 'generated_source_copies', 'binaries', 'captured_array_dumps'))
    index
  end
end

if $PROGRAM_NAME == __FILE__
  resume = !!ARGV.delete('--resume')
  abort 'Usage: export_observer_continuations.rb EVALUATION BATCH_ID [--resume]' unless ARGV.size == 2
  ObserverContinuationsExport.run(root: File.expand_path('..', __dir__), evaluation: File.expand_path(ARGV[0]), batch_id: ARGV[1], resume: resume)
end
