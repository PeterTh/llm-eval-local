require "json"
require "fileutils"
require "open3"
require "time"
require "/tmp/opencode-go-output-limit-controller-20261021.F2iMc4/tools/opencode_campaign_queue"

def checked(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{err}\n#{out}" unless status.success?
  out
end

queue_root = "/home/petert/llm_para_campaigns/20261019-134152-opencode-go-queue"
queue_path = File.join(queue_root, "queue.json")
queue = JSON.parse(File.read(queue_path))
controller = queue.fetch("controller_directory")
amendment = queue.fetch("runtime_amendment")
receipt = JSON.parse(File.read(File.join(amendment, "amendment.json")))
raise "Wrong controller" unless queue.fetch("controller_source_commit") == receipt.fetch("source_commit")
raise "Queue already active" if checked("systemctl", "--user", "show", queue.fetch("generation_unit"), "-p", "ActiveState", "--value").strip == "active"
raise "Already resumed" if File.file?(File.join(amendment, "resume.json"))
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
driver = OpenCodeCampaignQueue.new(queue_root)
manifests = queue.fetch("campaigns").map do |root|
  path = File.join(root, "campaign.json")
  manifest = JSON.parse(File.read(path))
  raise "Runtime revision differs" unless manifest.fetch("runtime_source_commit") == receipt.fetch("source_commit")
  manifest.fetch("files").each do |relative, sha|
    raise "Runtime file changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == sha
  end
  dry = checked("ruby", File.join(manifest.fetch("runtime_root"), "run.rb"), "--production", "--continue=#{manifest.fetch('campaign_id')}")
  File.write(File.join(amendment, "#{manifest.fetch('campaign_id')}-dry-run.log"), dry)
  if File.file?(File.join(root, "preflight-gate.json"))
    driver.review_preflight(root, manifest, GenerationCampaign.new(root))
  end
  [path, manifest]
end
raise "Queue stopped by operator" if File.exist?(File.join(queue_root, "STOP"))
stamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
unit = "llm-opencode-go-advertised-limits-#{stamp}.service"
resume = { "resumed_at" => Time.now.utc.iso8601, "previous_unit" => queue.fetch("generation_unit"),
  "unit" => unit, "controller" => controller, "source_commit" => receipt.fetch("source_commit"),
  "preserved_observations" => 109, "rerun_ids" => receipt.fetch("affected_observations"),
  "superseded_source_commit" => receipt.fetch("superseded_source_commit"), "generation_runtime_changed" => true,
  "generation_settings_changed" => "Go response cap now matches advertised model output limit; other settings unchanged" }
manifests.each do |path, manifest|
  manifest["generation_unit"] = unit
  File.write(path, JSON.pretty_generate(manifest) + "\n")
end
queue["generation_unit"] = unit
File.write(queue_path, JSON.pretty_generate(queue) + "\n")
FileUtils.cp(__FILE__, File.join(amendment, "resume.rb"))
File.write(File.join(amendment, "resume.json"), JSON.pretty_generate(resume) + "\n")
puts checked("systemd-run", "--user", "--unit=#{unit}", "--description=OpenCode Go with advertised response limits; four scoped replacements",
  "--property=Type=exec", "--property=WorkingDirectory=#{controller}",
  "--property=StandardOutput=append:#{queue_root}/generation.log", "--property=StandardError=append:#{queue_root}/generation.log",
  "/usr/bin/ruby", File.join(controller, "tools/opencode_campaign_queue.rb"), "run", queue_root)
puts JSON.pretty_generate(resume)
