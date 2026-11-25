# frozen_string_literal: true
require "json"
require "tmpdir"
require "open3"
require "etc"
require "/home/petert/llm_eval/experiment/lib/codex_model_catalog"
raise "Run as llmtest" unless Process.uid == Etc.getpwnam("llmtest").uid
root = Dir.mktmpdir("gpt62-model-catalog-", "/tmp")
File.chmod(0755, root)
path = File.join(root, "model-catalog.json")
binary = "/home/llmtest/.codex/packages/standalone/releases/0.171.0-x86_64-unknown-linux-musl/bin/codex"
command = ["ruby", "/home/petert/llm_eval/experiment/tools/metadata/prepare_codex_catalog.rb",
  "--binary=#{binary}", "--output=#{path}", "--model=gpt-6.2-astra", "--effort=medium"]
output, error, status = Open3.capture3(*command)
raise "Native catalog preparation failed: #{error}" unless status.success?
receipt = JSON.parse(File.read(path + ".receipt.json"))
content = File.read(path)
models = %w[gpt-6.2-astra gpt-6.2-sol].to_h do |model|
  entry = CodexModelCatalog.verify!(content, receipt, version:"0.171.0", model:model, effort:"medium")
  [model, {"context_window"=>entry.fetch("context_window"), "sha256"=>Digest::SHA256.hexdigest(JSON.generate(entry)),
    "supported_reasoning_levels"=>entry.fetch("supported_reasoning_levels")}]
end
puts JSON.pretty_generate({ "path"=>path, "receipt"=>receipt.except("model_list_entry"), "verified_models"=>models,
  "collector_stdout_sha256"=>Digest::SHA256.hexdigest(output), "inferences_launched"=>0 })
