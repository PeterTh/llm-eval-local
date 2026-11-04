# frozen_string_literal: true
require_relative 'artifact_common'
require_relative 'supplemental_validation_registry'

# Bind the complete approved sweep, not just its exclusion registries. This is
# read-only verification: no generated program, compiler or benchmark is run.
class ValidationSweepReceipt
  include LocalEvalArtifact
  attr_reader :inputs, :case_configurations

  def initialize(reader, relative, expected_digest)
    @reader, @relative = reader, relative
    @root = File.dirname(relative)
    receipt_path = reader.path(relative)
    raise 'Sweep receipt digest differs' unless sha256(receipt_path) == expected_digest
    receipt = JSON.parse(File.read(receipt_path))
    raise 'Unsupported sweep receipt' unless receipt.fetch('schema_version') == 1 && receipt.fetch('benchmark_runs') == 0
    @inputs = { relative => expected_digest }
    receipt.fetch('files_sha256').each do |name, digest|
      raise 'Unsafe sweep evidence path' if name.start_with?('/') || name.split('/').include?('..')
      path = reader.path(File.join(@root, name))
      raise "Sweep evidence changed: #{name}" unless sha256(path) == digest
      @inputs[File.join(@root, name)] = digest
    end
    actual = regular_files(reader.path(@root)).map { |path| relative_path(reader.path('.'), path) }.sort
    raise 'Unpinned sweep files' unless actual == @inputs.keys.sort
    kept_bytes = @inputs.keys.reject { |path| path == relative }.sum { |path| File.size(reader.path(path)) }
    raise 'Sweep retention size differs' unless kept_bytes == receipt.fetch('retained_bytes')

    plan = read('plan.json')
    approval = read('shape-topology-full-authorization.json')
    completion = read('shape-topology-full-completion.json')
    unless approval.fetch('source') == 'user' && approval.fetch('approved') &&
        approval.fetch('scope') == 'full-shape-topology-sweep' && approval.fetch('benchmark_runs') == 0 &&
        completion.fetch('status') == 'complete' && completion.fetch('benchmark_runs') == 0
      raise 'Sweep authorization or completion differs'
    end
    @case_configurations, records = {}, {}
    receipt.fetch('cases').each do |label, summary|
      raise 'Unsafe sweep case label' unless label.match?(/\A[a-z0-9-]+\z/)
      own_receipt = read("#{label}/export.json")
      raise 'Per-case receipt differs from sweep' unless own_receipt == summary
      definition = summary.fetch('case')
      unless definition.fetch('id') == label && definition == LocalEvaluation::ShapeValidationCases.definitions.fetch(label)
        raise 'Unexpected sweep case definition'
      end
      list = read_jsonl(reader.path(File.join(@root, label, 'records.jsonl')))
      ids = list.map { |record| record.fetch('id') }
      raise 'Duplicate or unordered case records' unless ids == ids.uniq.sort
      raise 'Case execution/skip coverage differs' unless summary.fetch('records') == list.size &&
        summary.fetch('executed') == list.count { |r| r.key?('result') } && summary.fetch('skipped') == list.count { |r| r.key?('skipped') } &&
        list.all? { |r| r.key?('result') != r.key?('skipped') }
      reference = read("#{label}/reference.json")
      raise 'Reference definition differs' unless reference.fetch('definition') == definition
      output = reference.fetch('stdout')
      unless Digest::SHA256.hexdigest(output) == reference.fetch('stdout_sha256') &&
          reference.dig('result', 'passed') && reference.dig('result', 'source_commit') == reference.fetch('source_commit') &&
          reference.dig('result', 'definition') == definition && reference.dig('result', 'output_sha256') == reference.fetch('stdout_sha256')
        raise 'Reference digest or result binding differs'
      end
      binding_list = read("#{label}/build-bindings.json")
      bindings = binding_list.to_h { |binding| [binding.fetch('id'), binding] }
      unless bindings.size == binding_list.size && bindings.keys.sort == list.select { |r| r['result'] }.map { |r| r.fetch('id') }.sort
        raise 'Sweep build-binding coverage differs'
      end
      list.each do |record|
        record_key = "#{label}/#{record.fetch('id')}"
        raise 'Duplicate sweep result key' if records.key?(record_key)
        records[record_key] = record
        if record['result']
          verify_result(record, definition, reference)
          binding = bindings.fetch(record.fetch('id'))
          unless binding.fetch('binary_sha256') == record.dig('result', 'binary_sha256') &&
              binding.fetch('source_files_sha256') == Digest::SHA256.hexdigest(JSON.generate(record.fetch('source').fetch('source_files')))
            raise 'Sweep executable/source binding differs'
          end
        end
      end
      registry = SupplementalValidationRegistry.new(reader.path(File.join(@root, label, 'exclusions.json')))
      failed = list.select { |r| r['result'] && !r.dig('result', 'passed') }.map { |r| r.fetch('id') }
      raise 'Case exclusions differ from results' unless failed == registry.records.keys && failed.size == summary.fetch('failed')
      @case_configurations[label] = {
        'registry' => File.join(@root, label, 'exclusions.json'), 'records' => File.join(@root, label, 'records.jsonl'),
        'registry_sha256' => registry.digest, 'export_sha256' => sha256(reader.path(File.join(@root, label, 'export.json'))),
        'applied_ids' => failed, 'campaign_receipt' => relative, 'campaign_receipt_sha256' => expected_digest
      }
    end
    planned_keys = plan.fetch('groups').flat_map do |group|
      definition, backend = group.values_at('definition', 'backend')
      unless LocalEvaluation::ShapeValidationCases.for_backend(definition.fetch('benchmark'), backend).include?(definition)
        raise 'Sweep group uses the wrong case/backend'
      end
      group.fetch('row_ids').map { |id| "#{definition.fetch('id')}/#{id}" }
    end
    raise 'Sweep omitted or duplicated planned checks' unless planned_keys.uniq.size == planned_keys.size && planned_keys.sort == records.keys.sort
    expanded = plan.merge('groups' => plan.fetch('groups').map do |group|
      group.to_h do |key, value|
        key == 'row_ids' ? ['rows', value.map { |id| records.fetch("#{group.dig('definition', 'id')}/#{id}").fetch('source') }] : [key, value]
      end
    end)
    plan_digest = Digest::SHA256.hexdigest(JSON.pretty_generate(expanded) + "\n")
    raise 'Approved sweep plan does not reconstruct' unless plan_digest == approval.fetch('plan_sha256') && plan_digest == completion.fetch('plan_sha256')
    records.each_value do |record|
      next unless record['skipped']
      skip = record.fetch('skipped')
      basis = records.fetch(skip.fetch('failed_result_key'))
      unless Digest::SHA256.hexdigest(JSON.pretty_generate(skip) + "\n") == record.fetch('skipped_sha256') &&
          skip.fetch('id') == record.fetch('id') && skip.fetch('source_commit') == record.dig('source', 'source_commit') &&
          skip.fetch('plan_sha256') == plan_digest && basis.fetch('id') == record.fetch('id') && basis.dig('result', 'passed') == false &&
          basis.fetch('result_sha256') == skip.fetch('failed_result_sha256')
        raise 'Skipped sweep check has no intact same-program failure basis'
      end
    end
    failed = records.values.select { |r| r['result'] && !r.dig('result', 'passed') }.map { |r| r.fetch('id') }.sort
    executed, skipped = records.values.partition { |r| r.key?('result') }.map(&:size)
    unless records.size == plan.fetch('checks') && records.size == approval.fetch('planned_checks') &&
        records.size == receipt.fetch('planned_checks') && records.size == completion.fetch('accounted_checks') &&
        records.values.map { |r| r.fetch('id') }.uniq.size == plan.fetch('unique_programs') &&
        executed == receipt.fetch('executed_checks') && executed == completion.fetch('completed_checks') &&
        skipped == receipt.fetch('skipped_checks') && skipped == completion.fetch('skipped_checks') &&
        failed == failed.uniq && failed == receipt.fetch('failed_ids') && failed == completion.fetch('failed_ids') &&
        executed - failed.size == completion.fetch('passed_checks')
      raise 'Sweep completion totals or dispositions differ'
    end
  end

  def verify_configuration!(configuration)
    label = File.basename(File.dirname(configuration.fetch('registry')))
    raise 'Release configuration differs from complete sweep' unless configuration == @case_configurations.fetch(label)
  end

  private

  def read(name) = JSON.parse(File.read(@reader.path(File.join(@root, name))))

  def verify_result(record, definition, reference)
    result, source, logs = record.values_at('result', 'source', 'logs')
    unless %w[id source_commit source_path].all? { |field| result.fetch(field) == source.fetch(field) } &&
        record.fetch('id') == source.fetch('id') && result.fetch('definition') == definition && result.fetch('performance_measurement') == false &&
        Digest::SHA256.hexdigest(JSON.pretty_generate(result) + "\n") == record.fetch('result_sha256') &&
        logs.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) } == record.fetch('log_sha256') &&
        result.fetch('output_sha256') == Digest::SHA256.hexdigest(logs.fetch('stdout')) &&
        result.fetch('reference_sha256') == reference.fetch('stdout_sha256')
      raise 'Sweep result or source binding differs'
    end
    comparison = if !result.dig('execution', 'success')
      [false, "Supplemental correctness execution failed: exit #{result.dig('execution', 'exit_code')}, timeout #{result.dig('execution', 'timed_out')}."]
    elsif !result.fetch('internal_validation')
      [false, 'Supplemental internal check failed.']
    else
      numeric = validate(reference.fetch('stdout'), logs.fetch('stdout'), definition.fetch('benchmark'))
      numeric.first && definition['comparison'] == 'integer_hash' ? LocalEvaluation::ComparisonPolicy.integer_hashes(reference.fetch('stdout'), logs.fetch('stdout')) : numeric
    end
    stdout = logs.fetch('stdout')
    internal = stdout.include?('Validation: PASSED') && !stdout.include?('Validation: FAILED') && !stdout.include?('Validation fail')
    raise 'Sweep internal-verdict flag differs from output' unless internal == result.fetch('internal_validation')
    raise 'Sweep verdict does not reproduce' unless comparison == result.fetch('comparison') && comparison.first == result.fetch('passed')
  end
end
