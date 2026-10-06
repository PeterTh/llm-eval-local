require "json"
require "open3"
require "/home/petert/llm_eval/experiment/lib/generation_cleanup"

cleanup = GenerationCleanup.new
abort "llmtest is not idle; live cleanup test refused" unless cleanup.pids.empty?
child = Process.spawn("su", "-", "llmtest", "--shell=/bin/bash", "-c", "exec sleep 30", out: File::NULL, err: File::NULL)
begin
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  loop do
    pids = cleanup.pids
    raise "Unexpected test-account processes" if pids.size > 1
    if pids.size == 1
      name, status = Open3.capture2("ps", "-p", pids.first.to_s, "-o", "comm=")
      break if status.success? && name.strip == "sleep"
    end
    raise "Disposable sleep process did not start" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.05
  end
  report = cleanup.verify!
  raise "No test process was signalled" unless report.fetch("signal_attempts").size == 1
  Process.wait(child)
  child = nil
  raise "llmtest is not empty after the live test" unless cleanup.pids.empty?
  File.write("/tmp/opus55-generation.Lx4eWo/cleanup-live-test.json", JSON.pretty_generate(report) + "\n")
  puts JSON.pretty_generate(report)
ensure
  if child
    Process.kill("TERM", child) rescue Errno::ESRCH
    Process.wait(child) rescue Errno::ECHILD
  end
end
