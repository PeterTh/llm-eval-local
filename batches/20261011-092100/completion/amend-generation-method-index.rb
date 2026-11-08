# frozen_string_literal: true
require_relative 'artifact/tools/artifact_common'
require 'time'
campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
root = File.join(__dir__, 'artifact')
base = 'batches/20261011-092100/generation'
generation = JSON.parse(File.read(File.join(root, base, 'campaign.json')))
layout = JSON.parse(File.read(File.join(root, base, 'method-layout-original.json')))
raise 'Original method set differs' unless layout.keys.sort == generation.fetch('files').keys.sort
index = layout.to_h do |name, binding|
  relative = binding.fetch('path')
  raise 'Unsafe method path' if Pathname.new(relative).absolute? || relative.split('/').include?('..')
  raise 'Original method binding differs' unless binding.fetch('sha256') == generation.fetch('files').fetch(name) &&
    LocalEvalArtifact.sha256(File.join(root, relative)) == binding.fetch('sha256')
  [name, relative]
end
path = File.join(root, base, 'method-layout.json')
raise 'Compatibility index already exists' if File.exist?(path)
File.write(path, JSON.pretty_generate(index) + "\n")
receipt = {
  'amended_at' => Time.now.utc.iso8601, 'files' => index.size,
  'original_layout_sha256' => LocalEvalArtifact.sha256(File.join(root, base, 'method-layout-original.json')),
  'compatibility_index_sha256' => LocalEvalArtifact.sha256(path),
  'generation_helper_sha256' => LocalEvalArtifact.sha256(File.join(root, 'tools/fable51_generation_evidence.rb')),
  'policy' => 'Add the existing reader flat-path projection of the already verified original method layout. All amendment-aware layouts and source/digest bindings are retained; no sources, observations, measurements or scores change.'
}
File.write(File.join(campaign, 'generation-method-index-amendment.json'), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, campaign)
FileUtils.cp(File.join(campaign, 'generation-method-index-amendment.json'), File.join(root, 'batches/20261011-092100/completion'))
FileUtils.cp(__FILE__, File.join(root, 'batches/20261011-092100/completion'))
puts JSON.pretty_generate(receipt)
