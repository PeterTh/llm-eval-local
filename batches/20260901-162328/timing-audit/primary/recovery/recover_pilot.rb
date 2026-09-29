# frozen_string_literal: true

# Revalidate completed source-only responses after a diagnostic-item checker fix.
# Never call a model, alter original attempt metadata, or choose by verdict.
source, target, library = ARGV
abort "Usage: recover_pilot.rb ORIGINAL NEW TIMING_AUDIT_LIBRARY" unless source && target && library
require File.expand_path(library)
source = File.realpath(source)
target = File.realpath(target)
original = YAML.safe_load_file(File.join(source, "manifest.yaml"), aliases: false)
current = YAML.safe_load_file(File.join(target, "manifest.yaml"), aliases: false)
%w[inventory_sha256 prompt_template_sha256 result_schema_sha256 trial_ids_sha256].each do |key|
  raise "Changed audit input #{key}" unless original.fetch("artifacts").fetch(key) == current.fetch("artifacts").fetch(key)
end
raise "Changed source commit" unless original.fetch("generated_source") == current.fetch("generated_source")
raise "Original runner changed" unless TimingAudit.sha256_file(File.join(source, "runner-snapshot.rb")) == original.dig("artifacts", "runner_sha256")
records = TimingAudit.load_jsonl(File.join(target, "inventory.jsonl"))
validator = TimingAudit::ResultValidator.new(records)
copied = []
recovered = []
rejected = []
records.each do |record|
  id = record.fetch("id")
  attempts = Dir[File.join(source, "logs", id, "attempt-*")].sort
  attempts.each do |directory|
    destination = File.join(target, "logs", id, File.basename(directory))
    if File.exist?(destination)
      expected = Dir[File.join(directory, "*")].select { |path| File.file?(path) }.to_h { |path| [File.basename(path), TimingAudit.sha256_file(path)] }
      actual = Dir[File.join(destination, "*")].select { |path| File.file?(path) }.to_h { |path| [File.basename(path), TimingAudit.sha256_file(path)] }
      raise "Previously copied evidence changed" unless actual == expected
    else
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp_r(directory, destination)
    end
    events_path = File.join(directory, "events.jsonl")
    events = TimingAudit.load_jsonl(events_path)
    copied << { "program_id" => id, "attempt_directory" => File.basename(directory),
                "events_sha256" => TimingAudit.sha256_file(events_path),
                "metadata_present" => File.file?(File.join(directory, "metadata.yaml")),
                "usage" => events.reverse.find { |event| event["type"] == "turn.completed" }&.fetch("usage", nil),
                "diagnostics" => events.filter_map { |event| event.dig("item", "message") if event.dig("item", "type") == "error" } }
  end
  # Keep the earliest completed, schema-valid, source-matched response. Later
  # duplicate attempts are evidence, not an opportunity to pick another verdict.
  attempts.each do |directory|
    metadata_path = File.join(directory, "metadata.yaml")
    next unless File.file?(metadata_path)
    metadata = YAML.safe_load_file(metadata_path, aliases: false)
    next unless metadata["exit_code"] == 0 && !metadata["timed_out"]
    raise "Source mismatch" unless metadata.fetch("source_digest") == record.fetch("source_digest")
    raise "Runner mismatch" unless metadata.fetch("runner_sha256") == original.dig("artifacts", "runner_sha256")
    events_path = File.join(directory, "events.jsonl")
    raise "Event digest mismatch" unless metadata.fetch("events_sha256") == TimingAudit.sha256_file(events_path)
    raise "Stderr digest mismatch" unless metadata.fetch("stderr_sha256") == TimingAudit.sha256_file(File.join(directory, "stderr.log"))
    TimingAudit.verify_static_events!(events_path)
    message = TimingAudit.load_jsonl(events_path).reverse.find do |event|
      event["type"] == "item.completed" && event.dig("item", "type") == "agent_message"
    end
    begin
      result = JSON.parse(message.fetch("item").fetch("text"))
      validator.validate!(result, expected_id: id)
    rescue JSON::ParserError, KeyError, RuntimeError => error
      rejected << { "program_id" => id, "attempt_directory" => File.basename(directory), "reason" => error.message }
      next
    end
    result_path = File.join(target, "results", "#{id}.json")
    serialized = JSON.pretty_generate(result) + "\n"
    raise "Previously recovered response changed" if File.file?(result_path) && File.read(result_path) != serialized
    TimingAudit.atomic_write(result_path, serialized)
    TimingAudit::AuditVerifier.new(target, "trial").verify_result!(id, result)
    recovered << { "program_id" => id, "attempt_directory" => File.basename(directory),
                   "metadata_sha256" => TimingAudit.sha256_file(metadata_path),
                   "result_sha256" => TimingAudit.sha256_file(result_path), "static_only_verified" => true }
    break
  end
end
recovery = File.join(target, "recovery")
{ File.join(source, "manifest.yaml") => "initial-manifest.yaml",
  File.join(source, "runner-snapshot.rb") => "initial-runner-snapshot.rb",
  __FILE__ => "recover_pilot.rb" }.each do |path, name|
  TimingAudit.atomic_write(File.join(recovery, name), File.binread(path))
end
TimingAudit.atomic_write(File.join(recovery, "copied-attempts.jsonl"), TimingAudit.dump_jsonl(copied))
TimingAudit.atomic_write(File.join(recovery, "recovered-results.jsonl"), TimingAudit.dump_jsonl(recovered))
TimingAudit.atomic_write(File.join(recovery, "rejected-responses.jsonl"), TimingAudit.dump_jsonl(rejected))
TimingAudit.atomic_write(File.join(recovery, "README.md"), <<~README)
  # Initial pilot response recovery

  The initial event checker incorrectly rejected Codex diagnostic items saying
  code mode was disabled. These were not tool calls; the model turns completed.
  The coordinator was stopped after its in-flight workers completed. The original
  audit is preserved at `#{source}`. No validation was repeated.

  The corrected checker accepts diagnostic items, still rejects every tool item,
  and still requires a completed turn and schema-valid, source-matched response.
  Source inventory, prompt, schema, trial selection, and CLI restrictions are unchanged.
  #{recovered.size} earliest completed responses were recovered without another model
  call. All #{copied.size} original attempt logs were copied unchanged;
  #{copied.count { |attempt| !attempt.fetch("metadata_present") }} final in-flight
  attempts lack coordinator metadata and were not selected. Malformed responses
  are listed separately and were not accepted or edited.
  Recovered attempts retain their actual original runner hash and metadata.
  The initial manifest, initial runner, recovery procedure, chosen response hashes,
  and compact attempt diagnostics/usage are retained here. Raw logs remain at home,
  not in the compact Git artifact.
README
puts "Recovered #{recovered.size} source-only responses; preserved #{copied.size} attempts"
