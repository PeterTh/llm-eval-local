# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'time'

campaign = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation'
audit = '/home/petert/llm_timing_audit/20261106-terra61-ultra-codex'
source = File.join(__dir__, 'generated/20261105-131145')
output = File.join(campaign, 'pilot-source-quality-review.json')
raise 'Source pilot check already recorded' if File.exist?(output)
samples = [
  ['black-scholes_gpt-6.1-terra-ultra_hybrid_r1', 'valid', 'black-scholes/black_scholes.cpp', [[159, 160], [184, 215]],
   'Disjoint rank/device option partitions; completed device work is included and the canonical output uses MPI_MAX of complete local intervals.'],
  ['cholesky_gpt-6.1-terra-ultra_hybrid_r3', 'invalid', 'cholesky/cholesky.cpp', [[160, 199], [307, 329]],
   'Distributed matrix.factor work is enclosed by local timestamps and barriers, but only root-local duration is printed. A barrier pair alone does not prove the required maximum; the core reported timing issue is supported.'],
  ['roomsim_gpt-6.1-terra-ultra_mpi_r1', 'invalid', 'roomsim/roomsim.cpp', [[565, 574], [914, 964]],
   'Distributed rows with sequential local phase intervals. The canonical total sums root-local intervals, without global phase maxima; the validation-only Kij reduction is unrelated.'],
  ['spmv_gpt-6.1-terra-ultra_mpi_r5', 'valid', 'spmv/spmv.cpp', [[263, 287], [329, 355]],
   'Contiguous distributed CSR row blocks; complete repeated local SpMV work is timed, reduced with MPI_MAX, and printed under the canonical label. Gathering for validation/output follows timing.']
].map do |id, verdict, relative, ranges, finding|
  result_path = File.join(audit, 'results', id + '.json')
  result = JSON.parse(File.read(result_path))
  raise 'Pilot verdict changed' unless result.fetch('program_id') == id && result.fetch('verdict') == verdict
  path = File.join(source, id, relative)
  lines = File.readlines(path)
  raise 'Pilot source ranges differ' unless ranges.all? { |first, last| first > 0 && last >= first && last <= lines.size }
  { 'id' => id, 'verdict' => verdict, 'result_sha256' => Digest::SHA256.file(result_path).hexdigest,
    'source_file' => relative, 'source_sha256' => Digest::SHA256.file(path).hexdigest,
    'reviewed_ranges' => ranges, 'finding' => finding }
end
report = { 'schema_version' => 1, 'checked_at' => Time.now.utc.iso8601, 'passed' => true,
  'source_commit' => 'e8a5a56facfc3feedc8de8dc0cca41af590acd66',
  'method' => 'Primary-agent source-grounded usability check of four pilot outcomes, covering correct device completion/max aggregation, barrier-enclosed root-local timing, and phased timing. The full pilot verdict/evidence summaries were inspected. This does not replace independent review of priority cases.',
  'samples' => samples, 'work_count_or_timing_disagreement' => false,
  'limits' => 'Pilot usability only, not a full audit or a license to change computation. Synchronization labels are interpreted under the frozen timing contract; no simultaneous start is required when complete local intervals are correctly reduced with MPI_MAX.',
  'program_executions' => 0, 'compilation' => 0, 'benchmark_runs' => 0, 'program_changes' => 0,
  'driver_sha256' => Digest::SHA256.file(__FILE__).hexdigest }
File.write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.reject { |key, _| key == 'samples' })
