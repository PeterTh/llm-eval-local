require "tmpdir"
require "fileutils"
require "json"
require "time"
require "/tmp/opencode-go-output-limit-controller-20261021.F2iMc4/tools/opencode_observation"

raise "Must run as the evaluation account" unless Process.uid == Etc.getpwnam("llmtest").uid
reports = []
OpenCodeHarness::GO_OUTPUT_TOKEN_LIMITS.each_key do |model|
  root = Dir.mktmpdir("opencode-limit-inspection-", "/tmp")
  runner = nil
  begin
    workspace = File.join(root, "workspace")
    FileUtils.mkdir_p(workspace)
    profile = OpenCodeHarness::CAMPAIGN_PROFILES.values.find { |entry| entry["model"] == model }
    spec = { "id" => "output-limit-configuration-inspection", "state" => File.join(root, "private"),
      "workspace" => workspace, "model" => model, "effort" => profile.fetch("reasoning_effort"),
      "binary" => "/home/llmtest/.local/share/opencode-eval/versions/1.19.3/opencode",
      "auth_file" => "/home/llmtest/.local/share/opencode-eval/go-access/data/opencode/auth.json" }
    path = File.join(root, "spec.json")
    File.write(path, JSON.generate(spec))
    runner = OpenCodeObservationRunner.new(path)
    runner.prepare
    evidence = JSON.parse(File.read(File.join(spec.fetch("state"), "prepared.json")))
    runner.start_server
    runner.verify_server!(evidence)
    reports << { "checked_at" => Time.now.utc.iso8601, "inferences_launched" => 0,
      "model" => model, "policy" => evidence.fetch("output_token_policy"),
      "flags" => evidence.fetch("flags"), "resolved_model" => evidence.fetch("resolved_model"),
      "enabled_tools" => evidence.fetch("enabled_tools"),
      "binary_sha256" => evidence.fetch("binary_sha256"), "version" => evidence.fetch("version") }
  ensure
    pid = runner&.instance_variable_get(:@server_pid)
    if pid
      Process.kill("TERM", pid) rescue Errno::ESRCH
      begin
        Timeout.timeout(2) { Process.wait(pid) }
      rescue Timeout::Error
        Process.kill("KILL", pid) rescue Errno::ESRCH
        Process.wait(pid) rescue Errno::ECHILD
      rescue Errno::ECHILD
        nil
      end
    end
    runner&.instance_variable_get(:@server_log)&.close
    # Exact private inspection directory; no generated source or result lives here.
    FileUtils.remove_entry_secure(root)
  end
end
puts JSON.generate({ "configuration_inspections" => reports })
