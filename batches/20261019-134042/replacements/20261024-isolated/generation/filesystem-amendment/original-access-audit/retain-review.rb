require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
require "zlib"

CAMPAIGN = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
ROOT = "/home/petert/llm_para_experiments/20261019-134042"
SCAN = "/tmp/deepseek-contamination-marker-audit-final-20261023.json"
DEST = File.join(CAMPAIGN, "evaluation/contamination-audit-20261023")
PROFILE = "deepseek-v4.1-flash-oc-high"
DEFINITE = {
  "black-scholes_cuda_r4" => ["prior_agent_session", [47, 71, 185], "Read prior Copilot plans and retained reference output; later invoked the evaluator against it."],
  "black-scholes_hybrid_r1" => ["prior_program_source", [74, 88, 130, 135], "Read previous GPT-4.1, GPT-5.2, Opus 4.6 and Sol sources, plus recorded performance."],
  "cahn-hilliard_cuda_r3" => ["prior_agent_session", [83, 95, 116], "Read prior Copilot/Codex session content and validation outcomes. The separate Qwen-labelled source is unchanged sequential input and is not the basis for this finding."],
  "cahn-hilliard_cuda_r4" => ["prior_program_source", [117, 183, 187], "Read prior GPT-4.1 CUDA implementation; also inspected/tested prior retained artifacts."],
  "cahn-hilliard_omp_r1" => ["prior_program_source", [513, 549, 554, 571], "Selected the previous Opus-5 winner from scored results, read/copied its source, then stripped comments/diagnostics into the submission."],
  "cholesky_hybrid_r2" => ["prior_program_source", [131, 135, 139, 143], "Read Opus-5.5 hybrid source and previous generated build definitions."],
  "cholesky_hybrid_r5" => ["prior_program_source", [70, 104, 117, 179], "Read Opus-4.6 hybrid source and previous benchmark/scoring data."],
  "roomsim_cuda_r1" => ["prior_program_source", [148, 160, 164], "Read prior GPT-4.1 CUDA implementation excerpts, including the random-generator/kernel code."],
  "roomsim_cuda_r2" => ["prior_analysis_report", [46], "Read the retained Sol-6.1 roomsim regression adjudication for a previous Luna implementation."],
  "roomsim_cuda_r4" => ["prior_analysis_report", [48, 58, 181], "Read the previous roomsim regression adjudication and Fable followup, as well as retained validation reference outputs."],
  "roomsim_hybrid_r1" => ["prior_analysis_report", [18, 33], "Read the previous roomsim regression adjudication and evaluator scripts."],
  "roomsim_hybrid_r4" => ["prior_agent_session", [247, 255, 259], "Read a previous Copilot roomsim checkpoint and searched earlier model transcript content."],
  "unstructured_hybrid_r5" => ["prior_program_source", [70, 177, 238, 266, 358], "Read earlier DeepSeek and Sol implementations and retained benchmark data."]
}.freeze
EVALUATOR_ONLY = {
  "black-scholes_cuda_r5" => [42, 59, 63, 291],
  "black-scholes_hybrid_r2" => [87, 96, 141, 367],
  "cahn-hilliard_cuda_r5" => [61, 69, 73],
  "cahn-hilliard_hybrid_r3" => [53, 60, 65],
  "cholesky_cuda_r5" => [26, 34, 38, 42],
  "cholesky_hybrid_r1" => [37, 41, 48, 378],
  "matmul_cuda_r1" => [131, 140, 145],
  "matmul_omp_r3" => [265],
  "qtclustering_omp_r1" => [154, 158, 169],
  "roomsim_hybrid_r5" => [55, 60, 65],
  "roomsim_mpi_r1" => [32, 33, 41]
}.freeze
EXCEPTIONS = {
  "cahn-hilliard_hybrid_r1" => [[41, 45], "The Qwen-labelled files were byte-identical to the supplied sequential Cahn-Hilliard files; the transcript also records identical hashes before any edits."],
  "roomsim_hybrid_r3" => [[32], "Read the same untouched sequential Cahn-Hilliard input in the stale Qwen-labelled workspace; no generated parallel solution was present."],
  "roomsim_cuda_r3" => [[68, 72], "Only a binary differs/equal comparison against an old generated source was revealed, not its contents. The subsequently compiled source was the original sequential input."],
  "qtclustering_hybrid_r2" => [[25, 29, 33], "Prior generated-source trees were empty; no previous program content was obtained."],
  "black-scholes_mpi_r2" => [[28, 29], "Read original shared sequential helper/build material and benchmark repository documentation, not generated solutions or retained evaluation results."],
  "qtclustering_omp_r3" => [[64, 68, 72], "Read/compiled the same original sequential source and common headers from a frozen input copy."],
  "unstructured_mpi_r5" => [[34, 38, 42], "Read/compiled original sequential source from a frozen input copy, not a previous generated implementation."]
}.freeze

def id(short)
  benchmark, backend, repetition = short.split("_")
  "#{benchmark}_#{PROFILE}_#{backend}_#{repetition}"
end

def selected_events(observation, lines)
  wanted = lines.to_h { |line| [line, true] }
  selected = []
  File.foreach(File.join(ROOT, observation, "output.txt")).with_index(1) do |text, number|
    next unless wanted[number]
    event = JSON.parse(text)
    state = event.fetch("part").fetch("state")
    output = state["output"].to_s
    raise "Selected evidence is not a completed read: #{observation}:#{number}" unless state["status"] == "completed" && !output.empty?
    selected << { "line" => number, "tool" => event.dig("part", "tool"), "input" => state["input"],
      "exit_code" => state.dig("metadata", "exit"), "output_bytes" => output.bytesize,
      "output_sha256" => Digest::SHA256.hexdigest(output) }
  end
  raise "Missing selected event" unless selected.map { |e| e.fetch("line") } == lines.sort
  selected
end

raise "Refusing to overwrite audit evidence" if File.exist?(DEST)
scan = JSON.parse(File.read(SCAN))
raise "Wrong scope" unless scan.fetch("scope") == ROOT && scan.fetch("transcripts_scanned") == 220
raise "Overlap in classifications" unless (DEFINITE.keys & EVALUATOR_ONLY.keys).empty?
method_commit, status = Open3.capture2("git", "-C", "/home/petert/llm_eval/experiment", "rev-parse", "HEAD")
raise "Cannot read method commit" unless status.success?
records = scan.fetch("observations").map do |row|
  observation = row.fetch("id")
  raise "Transcript changed" unless Digest::SHA256.file(File.join(ROOT, observation, "output.txt")).hexdigest == row.fetch("transcript_sha256")
  short = observation.sub("_#{PROFILE}", "")
  result = row.slice("id", "transcript_sha256", "malformed_lines").merge(
    "marker_lines" => row.fetch("candidate_events").map { |e| e.fetch("line") })
  if (classification = DEFINITE[short])
    category, lines, explanation = classification
    result.merge!("classification" => category, "disposition" => "rerun", "reason" => explanation,
      "evidence" => selected_events(observation, lines))
  elsif (lines = EVALUATOR_ONLY[short])
    result.merge!("classification" => "evaluator_only_exposure", "disposition" => "pending_user_scope_decision",
      "reason" => "Successfully read evaluator/test-size/resource/scoring implementation or configuration, but no prior generated solution, model-session content or analysis report was found.",
      "evidence" => selected_events(observation, lines))
  elsif (entry = EXCEPTIONS[short])
    result.merge!("classification" => "reviewed_non_substantive_access", "disposition" => "retain",
      "reason" => entry[1], "evidence" => selected_events(observation, entry[0]))
  else
    result.merge!("classification" => row.fetch("candidate_events").empty? ? "no_marker_hits" : "no_substantive_exposure_found",
      "disposition" => "retain", "reason" => "Marker review found only current-observation material, listings/search paths, failed/empty reads, or self-created scratch files; no substantive prior solution/evaluator exposure was found.")
  end
  result
end
raise "Wrong finding counts" unless records.count { |r| r["disposition"] == "rerun" } == 13 && records.count { |r| r["disposition"] == "pending_user_scope_decision" } == 11
baseline = "/tmp/opencode-go-advertised-limit-0-20261021-1485970-bazrcq/benchmarks"
qwen = "/home/llmtest/evals/20260909-123111/cahn-hilliard_qwen-3.8-27B-udq6_omp_r1"
identity = %w[cahn-hilliard/cahn_hilliard.cpp cahn-hilliard/CMakeLists.txt].to_h do |relative|
  sha = Digest::SHA256.file(File.join(baseline, relative)).hexdigest
  raise "Untouched input identity differs" unless sha == Digest::SHA256.file(File.join(qwen, relative)).hexdigest
  [relative, sha]
end
report = { "schema_version" => 1, "recorded_at" => Time.now.utc.iso8601, "batch" => "20261019-134042",
  "state" => "audit_complete_evaluator_only_scope_pending", "method_commit" => method_commit.strip,
  "original_generated_source_commit" => "40ad0bc6da259d4584e75b8f23f43c77e9751b24",
  "timing_corrected_source_commit" => "65363cf3710daa9e0d3409306efee5a49e18c8dd",
  "scope" => "DeepSeek retained observations only. Other campaigns' transcripts were not audited.",
  "method" => "Marker scan of all 220 JSONL transcripts, then selected tool inputs/output excerpts and follow-through. Not a full-transcript reading or a source-similarity audit.",
  "limits" => "No proof of absence of unrecorded/obfuscated access. Mere markers, failed reads, empty historical trees, identical sequential inputs, and directory listings are not contamination findings.",
  "counts" => { "observations" => records.size, "coarse_marker_candidates" => scan.fetch("candidate_observations"),
    "definite_prior_material_exposure" => 13, "evaluator_only_scope_pending" => 11, "retain" => 196,
    "categories" => records.group_by { |r| r.fetch("classification") }.transform_values(&:size) },
  "definite_rerun_ids" => DEFINITE.keys.map { |short| id(short) },
  "evaluator_only_ids" => EVALUATOR_ONLY.keys.map { |short| id(short) },
  "replacement_policy" => "One fresh attempt per affected ID, with the same model/effort, input, timeout and advertised output allowance, under filesystem isolation; retain the replacement regardless of correctness or performance, with no best-of selection. Revalidate/review/benchmark only replaced IDs.",
  "unchanged_sequential_input_check" => { "path" => qwen, "sha256" => identity },
  "marker_scan_sha256" => Digest::SHA256.file(SCAN).hexdigest, "observations" => records }
FileUtils.mkdir_p(DEST, mode: 0700)
File.write(File.join(DEST, "review.json"), JSON.pretty_generate(report) + "\n")
File.write(File.join(DEST, "definite-rerun-ids.txt"), report.fetch("definite_rerun_ids").join("\n") + "\n")
File.write(File.join(DEST, "evaluator-only-ids.txt"), report.fetch("evaluator_only_ids").join("\n") + "\n")
Zlib::GzipWriter.open(File.join(DEST, "marker-scan.json.gz")) { |file| file.write(File.binread(SCAN)) }
FileUtils.cp(__FILE__, File.join(DEST, "retain-review.rb"))
%w[generation-isolation-regressions-20261023.log generation-isolation-systemd-regressions-20261023.log generation-isolation-preflight-20261023.log].each do |name|
  FileUtils.cp(File.join("/tmp", name), File.join(DEST, name))
end
puts JSON.pretty_generate(report.slice("state", "method_commit", "counts", "definite_rerun_ids", "evaluator_only_ids"))
