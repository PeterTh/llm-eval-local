# frozen_string_literal: true
require "json"
require "open3"
require "time"
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
output, status = Open3.capture2e("ruby", "-Itest", "-e", 'Dir["test/test_*.rb"].sort.each { |file| require_relative file }',
  chdir: "/home/petert/llm_eval/experiment")
File.write(File.join(__dir__, "regression-tests.log"), output)
receipt = { "checked_at" => Time.now.utc.iso8601, "exit_status" => status.exitstatus,
  "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - start,
  "summary" => output.lines.last(4).join.strip }
File.write(File.join(__dir__, "regression-tests.json"), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
exit status.exitstatus
