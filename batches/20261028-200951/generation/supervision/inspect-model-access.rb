# frozen_string_literal: true
# Metadata only: no thread, turn, inference, session scan, or configuration write.
require "json"
require "open3"
require "timeout"
require "time"

binary = "/home/llmtest/.codex/packages/standalone/releases/0.160.1-x86_64-unknown-linux-musl/bin/codex"
result = { "checked_at" => Time.now.utc.iso8601, "binary" => binary,
  "inference_requested" => false, "session_scan_performed" => false }
version, status = Open3.capture2(binary, "--version")
raise "Cannot inspect version" unless status.success?
result["version"] = version.strip
config = "/home/llmtest/.codex/config.toml"
text = File.file?(config) ? File.read(config) : ""
result["config_relevant_lines"] = text.lines.map(&:strip).select { |line|
  line.match?(/\A(?:model|model_reasoning_effort|model_provider|web_search)\s*=/) }
result["custom_provider_or_mcp_sections"] = text.lines.map(&:strip).select { |line|
  line.match?(/\A\[(?:model_providers|mcp_servers)[.\]]/) }
raise "Custom provider or MCP configuration needs review" unless result.fetch("custom_provider_or_mcp_sections").empty?
result["extra_instruction_or_hook_files"] = %w[
  /home/llmtest/.codex/AGENTS.md /home/llmtest/.codex/AGENTS.override.md
  /home/llmtest/AGENTS.md /home/llmtest/AGENTS.override.md
  /home/llmtest/evals/AGENTS.md /home/llmtest/evals/AGENTS.override.md
  /home/llmtest/.codex/hooks.json
].select { |path| File.exist?(path) }
stdin, stdout, stderr, process = Open3.popen3(binary, "app-server", "--stdio",
  "--disable", "apps", "--disable", "plugins", "--disable", "multi_agent", chdir: "/tmp", pgroup: true)
drain = Thread.new { stderr.each_line { |_line| } }
begin
  stdin.sync = true
  response = lambda do |id|
    loop do
      line = stdout.gets
      raise "App server closed before response" unless line
      message = JSON.parse(line)
      next unless message["id"] == id
      raise "Metadata request rejected: #{message.dig('error', 'code')}" if message["error"]
      break message.fetch("result")
    end
  end
  Timeout.timeout(40) do
    stdin.puts(JSON.generate({ "id" => 0, "method" => "initialize", "params" => {
      "clientInfo" => { "name" => "terra61_campaign_preparation", "version" => "1.0" }
    } }))
    response.call(0)
    stdin.puts(JSON.generate({ "method" => "initialized", "params" => {} }))
    stdin.puts(JSON.generate({ "id" => 1, "method" => "account/read", "params" => { "refreshToken" => false } }))
    account = response.call(1)
    result["auth_type"] = account.dig("account", "type")
    result["plan_type"] = account.dig("account", "planType")
    entries = []
    cursor = nil
    request_id = 2
    loop do
      params = { "limit" => 100, "includeHidden" => true }
      params["cursor"] = cursor if cursor
      stdin.puts(JSON.generate({ "id" => request_id, "method" => "model/list", "params" => params }))
      page = response.call(request_id)
      entries.concat(page.fetch("data"))
      cursor = page["nextCursor"]
      break unless cursor
      request_id += 1
      raise "Unexpected model pagination" if request_id > 5
    end
    result["requested_models"] = entries.select { |entry| entry["model"] == "gpt-6.1-terra" }.map { |entry|
      entry.slice("id", "model", "displayName", "hidden", "defaultReasoningEffort", "supportedReasoningEfforts") }
  end
ensure
  stdin.close unless stdin.closed?
  unless process.join(3)
    Process.kill("TERM", -process.pid) rescue Errno::ESRCH
    process.join(3)
  end
  stdout.close
  stderr.close
  drain.join(1)
end
puts JSON.pretty_generate(result)
