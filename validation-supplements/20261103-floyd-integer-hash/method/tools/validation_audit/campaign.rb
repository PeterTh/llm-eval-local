# frozen_string_literal: true
require_relative 'runner'

module ValidationAudit
  class Campaign
    FLOYD = { 'id' => 'floyd-integer-hash-v1', 'benchmark' => 'floydwarshall',
      'args' => %w[-v -r -n 512], 'comparison' => 'integer_hash', 'timeout' => 30 }.freeze

    def initialize(workspace:, evidence:)
      @workspace, @evidence = File.realpath(workspace), File.expand_path(evidence)
      @runner = Runner.new(workspace: @workspace, evidence: @evidence)
    end

    def inventory(benchmark)
      current = Inventory.new(benchmarks: [benchmark])
      filename = File.join(@evidence, "inventory-#{benchmark}.json")
      unless File.file?(filename)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rows = current.rows.map { |r| ValidationAudit.bind_source(r) }
        ValidationAudit.save(filename, { 'benchmark' => benchmark, 'release_commit' => current.release_commit,
          'release_csv_sha256' => current.release_digest, 'catalog_sha256' => current.catalog_digest,
          'source_binding_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
          'scope' => 'All currently external-validation-passing release observations, including later benchmark failures.', 'rows' => rows })
      end
      saved = ValidationAudit.read(filename)
      raise 'Release changed during audit' unless current.release_digest == saved.fetch('release_csv_sha256') && current.catalog_digest == saved.fetch('catalog_sha256')
      [current, saved]
    end

    def floyd_result(row, record, reference)
      path = File.join(@evidence, FLOYD.fetch('id'), row.fetch('id'), 'result.json')
      return ValidationAudit.read(path) if File.file?(path)
      if row.fetch('staged_source_sha256') == ValidationAudit.archived_source_digest(record)
        output = ValidationAudit.stdout(record)
        comparison = validate(reference, output, 'floydwarshall')
        comparison = LocalEvaluation::ComparisonPolicy.integer_hashes(reference, output) if comparison.first
        result = { 'id' => row.fetch('id'), 'source_commit' => row.fetch('source_commit'), 'source_path' => row.fetch('source_path'),
          'definition' => FLOYD, 'archived_validation' => row.fetch('validation_record'), 'staged_source_sha256' => row.fetch('staged_source_sha256'),
          'reference_sha256' => Digest::SHA256.hexdigest(reference), 'output_sha256' => Digest::SHA256.hexdigest(output),
          'internal_validation' => true, 'comparison' => comparison, 'passed' => comparison.first,
          'checked_at' => Time.now.utc.iso8601, 'new_execution' => false, 'performance_measurement' => false }
        ValidationAudit.save(path, result)
        result
      else
        @runner.check(row, FLOYD, reference: reference)
      end
    end

    def floyd(mode)
      current, saved = inventory('floydwarshall')
      rows = saved.fetch('rows')
      reference_path = File.join(RELEASE, 'data/validation/references/floydwarshall/validation_out_stdout.log')
      reference = File.read(reference_path)
      pilot_path = File.join(@evidence, 'floyd-pilot.json')
      if mode == 'pilot'
        raise 'Pilot already completed' if File.file?(pilot_path)
        selected = rows.group_by { |r| r.fetch('backend') }.values.flat_map { |group| [group.first, group[group.size / 2], group.last] }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = []
        @runner.with_host { selected.each { |row| results << floyd_result(row, current.records.fetch(row.fetch('id')), reference) } }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        counterexample = JSON.parse(File.read(File.join(RELEASE, 'analysis/notes/2026-11-03-winner-validity/evidence.json')))
          .fetch('counterexamples').find { |r| r.fetch('benchmark') == 'floydwarshall' }
        outputs = counterexample.fetch('outputs').map { |r| r.dig('stdout', 'text') }
        negative = LocalEvaluation::ComparisonPolicy.integer_hashes(*outputs)
        raise 'Known incorrect distance was accepted' if negative.first
        estimated = saved.fetch('source_binding_seconds') + elapsed / selected.size * rows.size * 2 + 600
        report = { 'case' => FLOYD, 'pilot_ids' => selected.map { |r| r.fetch('id') }, 'pilot_seconds' => elapsed,
          'source_binding_seconds' => saved.fetch('source_binding_seconds'), 'full_population' => rows.size,
          'estimated_full_seconds_conservative' => estimated, 'estimate_basis' => 'Whole pilot wall time per observation, doubled, plus source binding and ten minutes for verification/disposition.',
          'under_five_hours' => estimated < 5 * 3600, 'known_numerical_error_rejected' => !negative.first,
          'passed' => results.count { |r| r.fetch('passed') }, 'failed_ids' => results.reject { |r| r.fetch('passed') }.map { |r| r.fetch('id') },
          'archived_outputs_reused' => results.count { |r| r['new_execution'] == false },
          'new_correctness_executions' => results.count { |r| r.key?('execution') }, 'benchmark_runs' => 0 }
        ValidationAudit.save(pilot_path, report)
        puts JSON.pretty_generate(report)
      elsif mode == 'full'
        pilot = ValidationAudit.read(pilot_path)
        raise 'Full campaign needs approval: estimate is not below five hours' unless pilot.fetch('under_five_hours')
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = []
        @runner.with_host do
          rows.each_with_index do |row, index|
            results << floyd_result(row, current.records.fetch(row.fetch('id')), reference)
            if (index + 1) % 25 == 0 || !results.last.fetch('passed')
              puts JSON.generate(completed: index + 1, total: rows.size, failed: results.count { |r| !r.fetch('passed') }, last: row.fetch('id'))
              $stdout.flush
            end
          end
        end
        report = { 'case' => FLOYD, 'total' => rows.size, 'passed' => results.count { |r| r.fetch('passed') },
          'failed_ids' => results.reject { |r| r.fetch('passed') }.map { |r| r.fetch('id') },
          'archived_outputs_reused' => results.count { |r| r['new_execution'] == false },
          'new_correctness_executions' => results.count { |r| r.key?('execution') },
          'additional_full_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, 'benchmark_runs' => 0 }
        ValidationAudit.save(File.join(@evidence, 'floyd-completion.json'), report)
        puts JSON.pretty_generate(report)
      else
        raise 'Use pilot or full'
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  raise 'Usage: campaign.rb WORKSPACE EVIDENCE floyd pilot|full' unless ARGV.size == 4
  campaign = ValidationAudit::Campaign.new(workspace: ARGV[0], evidence: ARGV[1])
  raise 'Unsupported campaign' unless ARGV[2] == 'floyd'
  campaign.floyd(ARGV[3])
end
