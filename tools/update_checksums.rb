#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "open3"

require_relative "artifact_common"
require_relative "batch_checksums"

options = { root: File.expand_path("..", __dir__) }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby tools/update_checksums.rb [--root=PATH]"
  parser.on("--root=PATH", "Artifact repository root") { |value| options[:root] = value }
end.parse!

root = File.expand_path(options.fetch(:root))
git_root, status = Open3.capture2("git", "-C", root, "rev-parse", "--show-toplevel")
raise "not a Git working tree root: #{root}" unless status.success? && File.realpath(git_root.strip) == File.realpath(root)

checksum_path = File.join(root, "checksums.sha256")
BatchChecksums.run(root)
files = LocalEvalArtifact.regular_files(root).reject { |file| file == checksum_path }
lines = files.map do |file|
  "#{LocalEvalArtifact.sha256(file)}  #{LocalEvalArtifact.relative_path(root, file)}\n"
end
File.write(checksum_path, lines.join, mode: "wb")
puts "Wrote #{files.size} checksums to #{checksum_path}"
