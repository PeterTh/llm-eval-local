# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

template = "/home/petert/llm-eval-local/batches/20261102-030935/generation/pricing"
destination = "/tmp/gpt62-request-reader-20261125-ooeWyw"
raise "Reader already prepared" if File.exist?(File.join(destination, "read-request-usage.rb"))
reader = File.read(File.join(template, "read-request-usage.rb"))
library_require = 'require "/tmp/terra61-xhigh-codex-generation-20261102-2885611-16u7ra/experiment/lib/codex_usage"'
raise "Unexpected prior reader" unless reader.scan(library_require).size == 1
reader = reader.sub(library_require, 'require_relative "codex_usage"')
reader = reader.gsub("TerraRequestUsage", "Gpt62RequestUsage").gsub("20261102-030935", "20261123-155235")
scope = 'record.fetch("run_id").include?("_gpt-6.1-terra-xhigh_")'
raise "Unexpected old scope" unless reader.scan(scope).size == 1
reader = reader.sub(scope, 'record.fetch("run_id").match?(/_gpt-6\.2-(?:astra|sol)-medium_/)')
reader = reader.sub("records.size.between?(1, 220)", "records.size.between?(1, 440)")
test = File.read(File.join(template, "test-request-usage.rb"))
test = test.gsub("TerraRequestUsage", "Gpt62RequestUsage").gsub("terra-request-usage-test-", "gpt62-request-usage-test-")
test = test.gsub("20261102-030935", "20261123-155235").gsub("gpt-6.1-terra-xhigh", "gpt-6.2-astra-medium")
test = test.gsub("0.160.1", "0.171.0")
additional_tests = <<~RUBY

  class Gpt62RequestUsageTest
    def test_sol_profile_is_also_accepted
      @cwd = @cwd.sub("gpt-6.2-astra-medium", "gpt-6.2-sol-medium")
      assert_equal 2, Gpt62RequestUsage.recover(record, sessions_root: @root).fetch("request_count")
    end

    def test_unrelated_model_is_rejected
      @cwd = @cwd.sub("gpt-6.2-astra-medium", "gpt-6.1-sol-medium")
      assert_raises(RuntimeError) { Gpt62RequestUsage.recover(record, sessions_root: @root) }
    end
  end
RUBY
File.write(File.join(destination, "read-request-usage.rb"), reader)
File.write(File.join(destination, "test-request-usage.rb"), test + additional_tests)
library = File.join(__dir__, "observer-pipeline-v5/lib/codex_usage.rb")
FileUtils.cp(library, destination)
File.chmod(0755, destination)
Dir[File.join(destination, "*.rb")].each { |path| File.chmod(0644, path) }
out, err, ok = Open3.capture3("ruby", File.join(destination, "test-request-usage.rb"), "--seed", "20261125")
File.write(File.join(destination, "tests.log"), out + err)
raise "Reader regressions failed" unless ok.success? && out.include?("8 runs, 11 assertions, 0 failures, 0 errors, 0 skips")
report = {
  "prepared_at" => Time.now.utc.iso8601,
  "template" => template,
  "changes" => "Only library location, batch/profile scope, module/fixture names and maximum record count; exact native counter reconciliation unchanged. Two scope regression cases added.",
  "template_sha256" => %w[read-request-usage.rb test-request-usage.rb].to_h { |name| [name, Digest::SHA256.file(File.join(template, name)).hexdigest] },
  "prepared_sha256" => Dir[File.join(destination, "*")].select { |path| File.file?(path) }.to_h { |path| [File.basename(path), Digest::SHA256.file(path).hexdigest] },
  "code_library_sha256" => Digest::SHA256.file(library).hexdigest,
  "tests_passed" => true, "native_sessions_read" => false,
  "policy" => "Run only after generation and native validation are idle, before benchmarking; read exactly the existing 440 bound sessions, no glob or model calls."
}
File.write(File.join(destination, "preparation.json"), JSON.pretty_generate(report) + "\n")
puts out
puts JSON.generate(report.slice("prepared_at", "tests_passed", "native_sessions_read"))
