# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require "find"
require "json"
require "pathname"
require "set"
require "yaml"

module LocalEvalArtifact
  EXPECTED = {
    validation_records: 4_620,
    fully_valid: 3_825,
    benchmark_records: 3_825,
    benchmark_successes: 3_488,
    benchmark_failures: 337,
    score_records: 4_620,
    score_counts: {
      0 => 140, 1 => 142, 2 => 67, 3 => 47, 4 => 399, 5 => 337,
      6 => 731, 7 => 740, 8 => 983, 9 => 989, 10 => 45
    }.freeze
  }.freeze

  BACKENDS = %w[omp cuda mpi hybrid].freeze
  VALIDATION_STAGES = %w[
    basic_para validation_build validation_run internal_validation output_comparison
  ].freeze
  SHA256_RE = /\A[0-9a-f]{64}\z/

  module_function

  def load_yaml(path)
    YAML.safe_load_file(path, permitted_classes: [Time, Symbol], aliases: true)
  end

  def sha256(path)
    Digest::SHA256.file(path).hexdigest
  end

  def read_utf8(path)
    bytes = File.binread(path)
    text = bytes.force_encoding(Encoding::UTF_8)
    raise "non-UTF-8 text file: #{path}" unless text.valid_encoding?

    text
  end

  def regular_files(root, exclude_git: true)
    root = File.expand_path(root)
    files = []
    Find.find(root) do |path|
      relative = path.delete_prefix("#{root}/")
      if exclude_git && (relative == ".git" || relative.start_with?(".git/"))
        Find.prune if File.directory?(path)
        next
      end
      raise "symlink is not allowed: #{relative}" if File.symlink?(path)
      files << path if File.file?(path)
    end
    files.sort
  end

  def relative_path(root, path)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  end

  def read_jsonl(path)
    records = []
    File.foreach(path, chomp: true).with_index(1) do |line, line_number|
      raise "blank JSONL line at #{path}:#{line_number}" if line.empty?
      records << JSON.parse(line)
    rescue JSON::ParserError => e
      raise "invalid JSON at #{path}:#{line_number}: #{e.message}"
    end
    records
  end

  def write_jsonl(path, records)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "wb") do |file|
      records.each do |record|
        file.write(JSON.generate(record))
        file.write("\n")
      end
    end
  end

  def fully_valid?(record)
    VALIDATION_STAGES.all? { |stage| record.fetch("stages").fetch(stage) == true }
  end

  def parse_sidecar(path)
    value = File.read(path, encoding: Encoding::UTF_8).strip
    raise "invalid SHA-256 sidecar: #{path}" unless SHA256_RE.match?(value)

    value
  end
end
