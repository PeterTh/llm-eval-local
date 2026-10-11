# frozen_string_literal: true
require "json"
require "fileutils"
require "open3"
require "digest"
require "time"

scratch = File.dirname(__FILE__)
destination = "/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh/evaluation/mpi-split-evidence"
raise "Evidence already exists" if File.exist?(destination)
FileUtils.mkdir_p(destination)
library = "/usr/lib/x86_64-linux-gnu/libmpi.so.40.30.6"
binary = "/home/petert/llm_para_local_evaluation/20261010-sol61-validation/validation/qtclustering_gpt-6.1-sol-medium_hybrid_r2/qtclustering"
commands = {
  "packages" => ["dpkg-query", "-W", "libopenmpi3t64", "libopenmpi-dev", "openmpi-bin"],
  "library-symbols" => ["objdump", "-T", library],
  "split-type-disassembly" => ["objdump", "--disassemble=ompi_comm_split_type", library],
  "binding-disassembly" => ["objdump", "-d", "--start-address=0x78e70", "--stop-address=0x79116", library],
  "program-dynamic-section" => ["readelf", "-d", binary],
  "compile-layout-probe" => ["/usr/bin/gcc-13", "-std=c11", "-c", "-I/usr/include/x86_64-linux-gnu/openmpi",
    "-I/usr/include/x86_64-linux-gnu/openmpi/openmpi", File.join(scratch, "mpi_layout_probe.c"), "-o", File.join(scratch, "mpi_layout_probe.o")]
}
records = commands.to_h do |name, argv|
  stdout, stderr, status = Open3.capture3(*argv)
  raise "Static evidence check failed: #{name}: #{stderr}" unless status.success?
  File.write(File.join(destination, "#{name}.stdout.txt"), stdout)
  File.write(File.join(destination, "#{name}.stderr.txt"), stderr)
  [name, { "argv" => argv, "exit_code" => status.exitstatus,
    "stdout_sha256" => Digest::SHA256.hexdigest(stdout), "stderr_sha256" => Digest::SHA256.hexdigest(stderr) }]
end
%w[openmpi-v4.1.6-comm.c openmpi-v4.1.6-comm_split_type.c mpi_layout_probe.c retain-evidence.rb].each do |name|
  FileUtils.cp(File.join(scratch, name), destination)
end
files = Dir[File.join(destination, "*")].select { |p| File.file?(p) }.to_h { |p|
  [File.basename(p), Digest::SHA256.file(p).hexdigest]
}
report = {
  "created_at" => Time.now.utc.iso8601, "purpose" => "Static facts for one supplemental timing review; no program execution",
  "library" => library, "library_sha256" => Digest::SHA256.file(library).hexdigest,
  "generated_binary_sha256" => Digest::SHA256.file(binary).hexdigest,
  "mpi_link_target" => File.realpath("/usr/lib/x86_64-linux-gnu/openmpi/lib/libmpi.so"),
  "sources" => {
    "openmpi-v4.1.6-comm.c" => "https://raw.githubusercontent.com/open-mpi/ompi/v4.1.6/ompi/communicator/comm.c",
    "openmpi-v4.1.6-comm_split_type.c" => "https://raw.githubusercontent.com/open-mpi/ompi/v4.1.6/ompi/mpi/c/comm_split_type.c"
  },
  "commands" => records, "files_sha256" => files,
  "generated_program_runs" => 0, "probe_linked" => false, "probe_executed" => false,
  "scope" => "Pinned local Open MPI library; no general portability claim and no timing verdict supplied to the reviewer"
}
File.write(File.join(destination, "evidence.json"), JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report.slice("library_sha256", "mpi_link_target", "generated_program_runs", "probe_executed"))
