#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

require_relative "artifact_common"

options = { root: File.expand_path("..", __dir__) }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby tools/update_checksums.rb [--root=PATH]"
  parser.on("--root=PATH", "Artifact repository root") { |value| options[:root] = value }
end.parse!

root = File.expand_path(options.fetch(:root))
raise "not a Git working tree: #{root}" unless File.directory?(File.join(root, ".git"))

checksum_path = File.join(root, "checksums.sha256")
files = LocalEvalArtifact.regular_files(root).reject { |file| file == checksum_path }
lines = files.map do |file|
  "#{LocalEvalArtifact.sha256(file)}  #{LocalEvalArtifact.relative_path(root, file)}\n"
end
File.write(checksum_path, lines.join, mode: "wb")
puts "Wrote #{files.size} checksums to #{checksum_path}"
