# frozen_string_literal: true
require "json"
require "digest"

module BeamCanaryRunnerAmendment
  REPORT = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation/canary-runner-amendment.json"
  module_function

  def verify!(runner, expected_original_digest)
    report = JSON.parse(File.read(REPORT))
    unless report.fetch("original_runner_sha256") == expected_original_digest &&
        report.fetch("amended_runner_sha256") == Digest::SHA256.file(runner).hexdigest &&
        report.fetch("scope") == "canary disposition gate and explicit orchestration provenance only"
      raise "Campaign runner amendment differs"
    end
    report.fetch("inputs_sha256").each do |path, sha|
      raise "Runner amendment input changed: #{path}" unless Digest::SHA256.file(path).hexdigest == sha
    end
    report
  end
end
