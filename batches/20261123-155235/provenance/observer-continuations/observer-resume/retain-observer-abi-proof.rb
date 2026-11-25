# frozen_string_literal: true
require 'json'
require 'open3'
require 'digest'
require 'fileutils'
require 'time'

campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
evidence = File.join(campaign, 'observer-resume')
output = File.join(evidence, 'abi-source-review.json')
raise 'Proof already retained' if File.exist?(output)
id = 'black-scholes_gpt-6.2-sol-medium_hybrid_r2'
root = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation'
binary = File.join(root, 'validation', id, 'black_scholes')
digest = Digest::SHA256.file(binary).hexdigest
raise 'Reviewed binary changed' unless digest == '4924109e91d77d89df39a93eaf034d2ea2cff368fcc8a9545e5d98b9be88aec6'
symbol = '_Z14collectResultsiimmPKdP14ResultsSummaryRSt5arrayIdLm10EE'
out, err, status = Open3.capture3('objdump', '-d', '--disassemble=' + symbol, binary)
raise "Disassembly failed: #{err}" unless status.success? && out.include?('mov    %r8,%r14') && out.include?('mov    %rdx,%r12')
actual_path = File.join(evidence, 'pilot-full-array/actual.json')
actual = JSON.parse(File.read(actual_path))
observation = actual.fetch('observation')
fragments = observation.fetch('captured_fragments').sort_by { |row| row.fetch('rank') }
raise 'Inspected block shape differs' unless fragments.map { |row| row.fetch('elements') } == [2501, 2501, 2501, 2500] &&
  fragments.map { |row| row.fetch('rank') } == %w[rank-0 rank-1 rank-2 rank-3] && observation.fetch('observation_complete')
report = { 'checked_at' => Time.now.utc.iso8601, 'program_id' => id,
  'original_source_commit' => '7a0a8b8e28af48d4ee2525c13ced317726536b25',
  'source_blob' => '57e16f9abfa9bdae10d492dc9dfcfe01221bb687',
  'binary_sha256' => digest, 'symbol' => symbol, 'entry_instruction_hex' => 'f30f1efa',
  'abi' => 'Linux x86-64 System V: third integer-class argument ownCount in rdx; fifth argument const double* local in r8.',
  'source_inspection' => {
    'black-scholes/black_scholes.cpp:120-200' => 'Contiguous quotient/remainder partitions; GPU device assignments determine consecutive rank ranges. The pilot topology observes one device per rank.',
    'black-scholes/black_scholes.cpp:313-399' => 'Original summary consumes the local block, then receives each remaining rank in increasing order; Kahan/FNV and samples consume those observed values.',
    'black-scholes/black_scholes.cpp:468-487' => 'The existing -r mode retains every local price and passes its pointer and full count to collectResults after computation.' },
  'disassembly_prologue' => out.lines.first(45).join,
  'complete_reproducible_disassembly_sha256' => Digest::SHA256.hexdigest(out),
  'pilot_actual_sha256' => Digest::SHA256.file(actual_path).hexdigest,
  'observed_blocks' => fragments.map { |row| row.slice('rank', 'elements', 'sha256', 'boundary_spec') },
  'program_executions_in_this_static_review' => 0, 'compilation' => 0, 'program_changes' => 0,
  'scope' => 'One exact binary and the existing four-rank hybrid 10003-option correctness case. No claim for other executables, sizes or ABIs.' }
File.write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, evidence)
puts JSON.generate(report.slice('program_id', 'binary_sha256', 'scope'))
