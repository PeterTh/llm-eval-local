# frozen_string_literal: true
# Operator preprocessing only. No linking, generated-program execution or edits.
require 'json'
require 'yaml'
require 'digest'
require 'open3'
require 'shellwords'
require 'fileutils'
require 'time'

scratch = __dir__
campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
destination = File.join(campaign, 'cholesky-mpi-r2-topology-context')
raise 'Platform context already prepared' if File.exist?(destination)
id = 'cholesky_claude-fable-5.1-cc-medium_mpi_r2'
source = File.join(scratch, 'generated/20261011-092100', id, 'cholesky/cholesky.cpp')
validation = '/home/petert/llm_para_local_evaluation/20261107-fable51-medium-validation'
flags_path = File.join(validation, 'validation', id, 'CMakeFiles/cholesky.dir/flags.make')
header = '/usr/lib/x86_64-linux-gnu/openmpi/include/mpi.h'
sha = ->(path) { Digest::SHA256.file(path).hexdigest }
flags = File.readlines(flags_path).filter_map do |line|
  match = line.match(/\A(CXX_DEFINES|CXX_INCLUDES|CXX_FLAGS) = (.*)\n?\z/)
  [match[1], Shellwords.split(match[2])] if match
end.to_h
raise 'Build flag set changed' unless flags.keys.sort == %w[CXX_DEFINES CXX_FLAGS CXX_INCLUDES]
args = %w[CXX_DEFINES CXX_INCLUDES CXX_FLAGS].flat_map { |key| flags.fetch(key) }
compiler = '/usr/bin/g++-13'
command = [compiler, *args, '-E', '-P', source]
text, error, status = Open3.capture3(*command)
raise "Preprocessing failed: #{error}" unless status.success?
start = text.index('Node makeNode(int P, int rank) {')
raise 'Missing preprocessed function' unless start
finish = text.index("\ninline void flag_set", start)
raise 'Missing function boundary' unless finish
function = text[start...finish]
raise 'Unexpected active split branch' unless function.include?('MPI_Comm_split_type(') &&
  function.include?('MPI_COMM_TYPE_SHARED') && !function.include?('OMPI_COMM_TYPE_SOCKET')
macro_command = [compiler, *args, '-E', '-dM', source]
macros, macro_error, macro_status = Open3.capture3(*macro_command)
raise "Macro preprocessing failed: #{macro_error}" unless macro_status.success?
raise 'Socket identifier is defined as macro' if macros.match?(/^#define OMPI_COMM_TYPE_SOCKET\b/)
header_excerpt = File.readlines(header)[791...812].join
raise 'Header enum evidence changed' unless header_excerpt.include?('enum {') && header_excerpt.include?('OMPI_COMM_TYPE_SOCKET,')
support = File.join(scratch, 'experiment/lib/local_evaluation/support.rb')
support_excerpt = File.readlines(support)[1521...1543].join
raise 'MPI measurement profile changed' unless support_excerpt.include?('ppr:64:socket:PE=1') && support_excerpt.include?('"128"')
original_context = File.join(validation, 'timing-platform-context.txt')
context = File.read(original_context) + <<~CONTEXT

  Additional recorded-platform evidence for #{id}:
  The native GCC build's CXX_DEFINES is empty. Its exact include paths and CXX_FLAGS
  were replayed with GCC's preprocessing-only -E option, with no linking or execution.
  makeNode retains the MPI_COMM_TYPE_SHARED call and removes the
  OMPI_COMM_TYPE_SOCKET branch. The installed Open MPI 4.1.6 mpi.h declares
  OMPI_COMM_TYPE_SOCKET as an enum identifier, not a macro; the full translation
  unit's -dM macro listing has no OMPI_COMM_TYPE_SOCKET definition.
  Thus the source's #ifdef does not select a per-socket split on this toolchain.
  The experiment runs locally on the single host gpuc3, with 128 MPI ranks mapped
  ppr:64:socket:PE=1 to its two sockets; no remote MPI hosts or hostfile are used.
  Native validation and shape checks already ran on the same host. No new MPI
  process or generated binary was launched to prepare this context.

  Exact preprocessed makeNode (GCC -E -P; only this excerpt is retained):
  #{function}

  Installed mpi.h lines 792-812:
  #{header_excerpt}

  This supplies a compilation-branch and target-placement fact, not an adjudicated
  timing verdict. Re-evaluate whether it resolves the startup-dependency uncertainty,
  including the timing boundaries and the complete work/result dependencies.
  Do not extrapolate to another compiler/header or multi-host execution.
CONTEXT
FileUtils.mkdir_p(destination)
File.write(File.join(destination, 'platform-context.txt'), context)
File.write(File.join(destination, 'preprocessed-makeNode.txt'), function)
File.write(File.join(destination, 'mpi-header-excerpt.txt'), header_excerpt)
File.write(File.join(destination, 'benchmark-profile-excerpt.txt'), support_excerpt)
FileUtils.cp(flags_path, File.join(destination, 'native-build-flags.make'))
FileUtils.cp(__FILE__, destination)
report = {
  'prepared_at' => Time.now.utc.iso8601, 'program_id' => id,
  'source_sha256' => sha.call(source), 'source_commit' => 'e3a476e84284ddea4052c6e55e92439f10f38b1a',
  'compiler' => compiler, 'compiler_sha256' => sha.call(compiler),
  'native_build_flags_path' => flags_path, 'native_build_flags_sha256' => sha.call(flags_path),
  'mpi_header_path' => header, 'mpi_header_sha256' => sha.call(header),
  'native_pipeline_path' => support, 'native_pipeline_sha256' => sha.call(support),
  'commands' => [command, macro_command], 'exit_statuses' => [status.exitstatus, macro_status.exitstatus],
  'stderr' => [error, macro_error], 'full_preprocessed_sha256' => Digest::SHA256.hexdigest(text),
  'full_macro_listing_sha256' => Digest::SHA256.hexdigest(macros),
  'full_preprocessed_outputs_retained' => false,
  'context_sha256' => sha.call(File.join(destination, 'platform-context.txt')),
  'program_executions' => 0, 'linking' => 0, 'source_changes' => 0, 'scientific_verdict' => nil,
  'next_step' => 'Supply the bound context to a targeted Sol-6.1 continuation after the current adjudication pass; preserve its original uncertain review.'
}
File.write(File.join(destination, 'preprocessing-proof.json'), JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report.reject { |key, _| key == 'commands' })
