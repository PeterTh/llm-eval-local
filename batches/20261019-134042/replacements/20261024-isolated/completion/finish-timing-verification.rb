# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "time"
root = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/amendments/20261023-filesystem-isolation"
policy_path = File.join(root, "timing-handoff-policy.json")
policy = JSON.parse(File.read(policy_path))
driver = policy.fetch("driver")
source = "/tmp/deepseek-isolated-timing-review-20261024.rb"
before = File.read(driver)
after = File.read(source)
replacement = <<~'RUBY'.lines.map { |l| "    " + l }.join.chomp
  # The QT adjudication inventory covers every QT candidate, but only the
  # uncertainty/disagreement subset is sent to Sol. Do not demand blanket
  # adjudication for confident Luna results.
  verifier.run unless root == "#{boundary}-sol61"
RUBY
raise "Unexpected verification change" unless before.scan("    verifier.run\n").size == 1 && before.sub("    verifier.run", replacement) == after
raise "Previous driver changed" unless Digest::SHA256.hexdigest(before) == policy.fetch("review_sha256")
target = File.join(root, "evaluation/qt-optional-verification-fix.json")
raise "Already fixed" if File.exist?(target)
retained = Dir["/home/petert/llm_timing_audit/20261024-deepseek41-opencode-isolated*/results/*.json"].sort.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
raise "Unexpected completed review count" unless retained.size == 27
FileUtils.cp(driver, File.join(root, "timing-review-before-optional-check-fix.rb"))
FileUtils.cp(policy_path, File.join(root, "timing-policy-before-optional-check-fix.json"))
[driver, File.join(root, "timing-review.rb"), File.join(root, "evaluation/timing-review-driver.rb")].each { |path| FileUtils.cp(source, path) }
policy["review_sha256"] = Digest::SHA256.file(source).hexdigest
File.write(policy_path, JSON.pretty_generate(policy) + "\n")
report = { "fixed_at" => Time.now.utc.iso8601, "old_driver_sha256" => Digest::SHA256.hexdigest(before),
  "new_driver_sha256" => policy.fetch("review_sha256"), "retained_results" => retained,
  "cause" => "The final wrapper incorrectly demanded a Sol result for every QT inventory entry even when the established uncertainty-only plan selected none.",
  "correction" => "Use the existing QT subset verification from run_review/finalize, and independently verify only actual retained Sol responses. No extra Sol invocation is authorized or needed.",
  "scientific_review_policy_changed" => false }
File.write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(root, "evaluation/finish-timing-verification.rb"))
command = JSON.parse(File.read(File.join(root, "timing-handoff-launch.json"))).fetch("command")
system("systemctl", "--user", "reset-failed", "llm-deepseek41-isolated-timing-20261024.service") || raise("Reset failed")
system(*command) || raise("Finish verification launch failed")
puts JSON.pretty_generate(report.except("retained_results"))
