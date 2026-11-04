# frozen_string_literal: true
require_relative 'full_array_capture'

module ValidationAudit
  # Reconcile saved, byte-identical captures from ranks whose stdout is suppressed.
  # Does not execute programs, replace evidence, or relax numerical comparisons.
  module FullArrayReconcile
    CAPTURE_ERROR = 'Captured arrays do not match all printed result objects'
    module_function

    def select_identical_replicas(observation, stdout)
      raise 'Not an isolated correspondence problem' unless observation.fetch('errors') == [CAPTURE_ERROR] &&
        observation.fetch('observation_complete') == false
      printed = FullArrayCapture.output_objects(stdout)
      raise 'Printed result evidence differs' unless printed == observation.fetch('printed_objects')
      raise 'Empty or repeated printed names' if printed.empty? || printed.map { |r| r.fetch('name') }.uniq.size != printed.size
      objects = observation.fetch('objects')
      objects.each do |object|
        bytes = File.binread(object.fetch('local_path'))
        raise 'Captured bytes changed' unless bytes.bytesize == object.fetch('bytes') &&
          Digest::SHA256.hexdigest(bytes) == object.fetch('sha256') &&
          (bytes.empty? ? nil : FullArrayCapture.fnv(bytes)) == object.fetch('fnv1a64')
      end
      key = ->(object) { object.slice('name', 'elements', 'fnv1a64') }
      groups = objects.group_by(&key)
      raise 'Unmatched captures or outputs' unless groups.keys.sort_by(&:to_s) == printed.sort_by(&:to_s)
      raise 'No extra replicas to reconcile' unless objects.size > printed.size
      printed.map do |output|
        replicas = groups.fetch(output)
        identities = replicas.map { |r| r.slice('name', 'dtype', 'elements', 'bytes', 'sha256', 'fnv1a64') }.uniq
        raise 'Nonidentical replicas are ambiguous' unless identities.size == 1
        replicas.first
      end
    end

    def review(evidence, id)
      raise 'Unsafe ID' unless id.match?(/\A[A-Za-z0-9_.-]+\z/)
      root = File.join(evidence, 'full-array-pilot-01')
      plan = ValidationAudit.read(File.join(root, 'plan.json'))
      group = plan.fetch('groups').find { |g| g.fetch('pilot_rows').any? { |r| r.fetch('id') == id } }
      raise 'Not a planned pilot observation' unless group
      row = group.fetch('pilot_rows').find { |r| r.fetch('id') == id }
      directory = File.join(root, id)
      raise 'Comparison already exists' if File.exist?(File.join(directory, 'comparison.json'))
      path = File.join(directory, 'observation.json')
      observation = ValidationAudit.read(path)
      binding_path = File.join(evidence, 'bindings', id + '.json')
      binding = ValidationAudit.read(binding_path)
      raise 'Source/binary binding changed' unless binding.fetch('source_files') == row.fetch('source_files') &&
        ValidationAudit.sha(binding_path) == observation.fetch('binding_sha256') &&
        ValidationAudit.sha(binding.fetch('executable')) == observation.fetch('binary_sha256')
      stdout = File.read(File.join(directory, 'validation_stdout.log'))
      raise 'Output changed' unless Digest::SHA256.hexdigest(stdout) == observation.fetch('stdout_sha256')
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      selected = select_identical_replicas(observation, stdout)
      reconciled = observation.merge('objects' => selected, 'errors' => [], 'observation_complete' => true)
      reference_path = File.join(root, 'reference_' + group.fetch('benchmark'), 'observation.json')
      reference = ValidationAudit.read(reference_path)
      comparison = FullArrayCapture.compare(reference, reconciled)
      sparse = validate(File.read(File.join(File.dirname(reference_path), 'validation_stdout.log')), stdout, group.fetch('benchmark'))
      review_path = File.join(directory, 'capture-reconciliation.json')
      review = { 'id' => id, 'original_observation_sha256' => ValidationAudit.sha(path),
        'reference_observation_sha256' => ValidationAudit.sha(reference_path),
        'reason' => 'All extra captures are byte-identical replicas of printed arrays. One representative per printed name is unambiguous; no numerical policy change.',
        'selected_objects' => selected, 'captured_objects' => observation.fetch('objects').size,
        'method_sha256' => ValidationAudit.sha(__FILE__), 'reviewed_at' => Time.now.utc.iso8601,
        'program_runs' => 0, 'benchmark_runs' => 0, 'program_source_changes' => 0 }
      method_directory = File.join(evidence, 'full-array-methods', review.fetch('method_sha256'))
      FileUtils.mkdir_p(method_directory)
      method_path = File.join(method_directory, File.basename(__FILE__))
      if File.exist?(method_path)
        raise 'Review method archive changed' unless File.binread(method_path) == File.binread(__FILE__)
      else
        File.open(method_path, File::WRONLY | File::CREAT | File::EXCL) { |f| f.write(File.binread(__FILE__)) }
      end
      ValidationAudit.save(review_path, review)
      comparison.merge!('sparse_comparison' => sparse, 'source' => row,
        'observation_sha256' => ValidationAudit.sha(path),
        'observation_reconciliation_sha256' => ValidationAudit.sha(review_path),
        'total_check_seconds' => observation.fetch('total_seconds') + Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      comparison['passed'] &&= sparse.first
      ValidationAudit.save(File.join(directory, 'comparison.json'), comparison)
      puts JSON.pretty_generate(comparison.reject { |k, _| k == 'source' })
    end
  end
end

if $PROGRAM_NAME == __FILE__
  raise 'Usage: full_array_reconcile.rb EVIDENCE ID' unless ARGV.size == 2
  ValidationAudit::FullArrayReconcile.review(*ARGV)
end
