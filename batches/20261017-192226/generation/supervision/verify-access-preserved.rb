require "json"
require "digest"
require "etc"
raise "Expected evaluation account" unless Process.uid == Etc.getpwnam("llmtest").uid

expected = {
  "/home/llmtest/.config/opencode/opencode.jsonc" => "4e901f9e457c8d52ab31f9fb4ea637a8c9104ebdbf23fe8b3600f35ad46d4a61",
  "/home/llmtest/.config/opencode/package-lock.json" => "3aee2b7c210e77272f134020e8d96ca368031199fac9534df91afdf5b3cd6bf8",
  "/home/llmtest/.config/opencode/package.json" => "00b9623ce1e46bb9a4d6bc17a6428516140bbb27d44d05ec9a776fa776f34ee7",
  "/home/llmtest/.opencode/package-lock.json" => "815f435618f027eed0dc120edac10408a1ca5b08c34284801feb5b937073070d",
  "/home/llmtest/.opencode/package.json" => "00b9623ce1e46bb9a4d6bc17a6428516140bbb27d44d05ec9a776fa776f34ee7"
}
unchanged = expected.all? { |path, hash| Digest::SHA256.file(path).hexdigest == hash }
old = JSON.parse(File.read("/home/llmtest/.local/share/opencode/auth.json"))
isolated = JSON.parse(File.read("/home/llmtest/.local/share/opencode-eval/access/data/opencode/auth.json"))
native = JSON.parse(File.read("/home/llmtest/.codex/auth.json"))
old_types = old.transform_values { |value| value.fetch("type") }
isolated_types = isolated.transform_values { |value| value.fetch("type") }
native_id = native.dig("tokens", "account_id")
isolated_id = isolated.dig("openai", "accountId")
same_account = native_id && isolated_id ? native_id == isolated_id : nil
raise "Prior configuration changed" unless unchanged
raise "Unexpected subscription provider" unless isolated_types == { "openai" => "oauth" }
raise "Prior outputs are readable" if File.readable?("/home/petert/llm_para_experiments")
raise "Telemetry exporter inherited" unless ENV.keys.grep(/\AOTEL_/).empty?
puts JSON.pretty_generate({
  "prior_opencode_configuration_unchanged" => unchanged,
  "prior_opencode_auth_provider_types" => old_types,
  "isolated_auth_provider_types" => isolated_types,
  "same_account_as_native_codex" => same_account,
  "prior_outputs_readable" => false,
  "inherited_otel_variables" => [],
  "credential_values_retained" => false
})
