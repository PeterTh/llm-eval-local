# frozen_string_literal: true
require_relative 'artifact_common'

module ObserverContinuations
  module_function

  def verify(root:, campaign:, index:)
    raise 'Observer continuation batch differs' unless index.fetch('batch') == campaign.fetch('id')
    check_file = lambda do |binding|
      relative = binding.fetch('path')
      raise 'Unsafe continuation path' if relative.start_with?('/') || relative.split('/').any? { |part| ['', '.', '..'].include?(part) }
      path = File.join(root, relative)
      raise 'Continuation evidence changed' unless File.file?(path) && !File.symlink?(path) && LocalEvalArtifact.sha256(path) == binding.fetch('sha256')
      path
    end
    previous = nil
    known_runs = {}
    index.fetch('phases').each_value do |phase|
      phase.fetch('files').each_value { |binding| check_file.call(binding) }
      receipt = JSON.parse(File.read(check_file.call(phase.fetch('receipt'))))
      raise 'Continuation source differs' unless receipt.fetch('source_commit') == campaign.fetch('source_commit')
      # A compatibility pilot may be superseded by a successor imported from
      # the same original run. Bind that branch, not an invented linear chain.
      initial = receipt.fetch('initial_run')
      known_runs[initial] = receipt.fetch('initial_pipeline') if known_runs.empty?
      raise 'Broken observer continuation graph' unless known_runs.fetch(initial) == receipt.fetch('initial_pipeline')
      successor = receipt.fetch('successor_run')
      raise 'Duplicate observer successor' if known_runs.key?(successor)
      known_runs[successor] = receipt.fetch('successor_pipeline')
      %w[initial_pipeline successor_pipeline].each do |key|
        pipeline = receipt.fetch(key)
        layout = index.fetch('method_layouts').fetch(pipeline.fetch('sha256'))
        raise 'Incomplete observer method' unless layout.fetch('commit').match?(/\A[0-9a-f]{40}\z/) && layout.fetch('files').keys.sort == pipeline.fetch('files').keys.sort
        layout.fetch('files').each do |name, binding|
          check_file.call(binding)
          raise 'Observer method differs' unless binding.fetch('sha256') == pipeline.fetch('files').fetch(name)
        end
      end
      previous = receipt
    end
    raise 'Missing continuation chain' unless previous
    manifest = LocalEvalArtifact.load_yaml(File.join(root, campaign.fetch('manifest')))
    raise 'Final observer method differs' unless previous.fetch('successor_pipeline') == manifest.fetch('pipeline_source')
    true
  end
end
