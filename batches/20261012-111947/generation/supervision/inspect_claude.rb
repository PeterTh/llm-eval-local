require "json"
require "digest"
require "open3"
require "etc"

raise "Inspection must run as llmtest" unless Process.uid == Etc.getpwnam("llmtest").uid
binary = File.realpath("/home/llmtest/.local/bin/claude")
version, version_status = Open3.capture2({"DISABLE_AUTOUPDATER" => "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" => "1"}, binary, "--version")
raise "Claude version inspection failed" unless version_status.success?
supported, supported_status = Open3.capture2("rg", "-a", "-o", "claude-haiku-5-5", binary)
raise "Requested model is absent from the installed executable" unless supported_status.success?
instructions = %w[/CLAUDE.md /home/CLAUDE.md /home/llmtest/CLAUDE.md /home/llmtest/evals/CLAUDE.md
  /.claude /home/.claude /home/llmtest/evals/.claude].select { |path| File.exist?(path) }
puts JSON.pretty_generate({
  "binary_path" => binary, "binary_sha256" => Digest::SHA256.file(binary).hexdigest,
  "version" => version.strip.delete_suffix(" (Claude Code)"),
  "requested_model" => "claude-haiku-5-5", "binary_model_names" => supported.lines.map(&:strip).uniq,
  "reasoning_effort" => "medium", "credentials_readable" => File.readable?("/home/llmtest/.claude/.credentials.json"),
  "extra_instruction_files" => instructions,
  "custom_skills" => Dir["/home/llmtest/.claude/skills/**/SKILL.md", "/home/llmtest/.agents/skills/**/SKILL.md"],
  "prior_outputs_readable" => File.readable?("/home/petert/llm_para_experiments/.git/config"),
  "availability_gate" => "The reusable production preflight must report this exact model, successful completion and exact token accounting."
})
