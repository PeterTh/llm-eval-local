require "json"
require "digest"
require "open3"
require "shellwords"

root = "/home/llmtest/.codex"
binary = File.realpath("/home/llmtest/.local/bin/codex")
cache_path = File.join(root, "models_cache.json")
cache = File.file?(cache_path) ? JSON.parse(File.read(cache_path)) : {}
models = Array(cache["models"]).select { |m| m["slug"] == "gpt-6.1-sol" }
config_path = File.join(root, "config.toml")
config_lines = File.file?(config_path) ? File.readlines(config_path).select { |line|
  line.match?(/\A\s*(?:model|model_reasoning_effort|model_provider|web_search|history|\[features\]|\[mcp_servers|\[profiles|\[history\]|\[model_providers)/)
} : []
config_text = File.read(config_path)
section = ""
keys = config_text.lines.filter_map do |line|
  if line.match?(/\A\s*\[/)
    section = line.strip
    section unless section.start_with?("[projects.")
  elsif !section.start_with?("[projects.") && (key = line[/\A\s*([A-Za-z0-9_.-]+)\s*=/, 1])
    key
  end
end
extra_instructions = %w[/home/llmtest/.codex/AGENTS.md /home/llmtest/.codex/AGENTS.override.md
  /home/llmtest/AGENTS.md /home/llmtest/AGENTS.override.md /home/llmtest/evals/AGENTS.md
  /home/llmtest/evals/AGENTS.override.md /home/llmtest/.codex/hooks.json].select { |p| File.exist?(p) }
params = File.read("/home/petert/llm_eval/experiment/experiment.rb")[/^PARAMS_CODEX = '([^']+)'$/, 1]
features, feature_status = Open3.capture2e(binary, *Shellwords.split(params), "features", "list")
raise "Feature inspection failed" unless feature_status.success?
puts JSON.pretty_generate({
  "binary_path" => binary, "binary_sha256" => Digest::SHA256.file(binary).hexdigest,
  "cache_file" => cache_path, "cache_updated_at" => cache["fetched_at"],
  "requested_model" => models.map { |m| m.slice("slug", "display_name", "supported_reasoning_levels", "default_reasoning_level", "visibility", "supported_in_api", "context_window") },
  "config_relevant_lines" => config_lines.map(&:strip), "config_key_names" => keys,
  "config_sha256" => Digest::SHA256.file(config_path).hexdigest,
  "extra_instruction_or_hook_files" => extra_instructions,
  "custom_skills" => Dir["/home/llmtest/.agents/skills/**/SKILL.md", "/home/llmtest/.codex/skills/**/SKILL.md"],
  "prior_outputs_readable" => File.readable?("/home/petert/llm_para_experiments/.git/config"),
  "codex_flags" => params, "effective_features" => features.lines.map(&:strip)
})
