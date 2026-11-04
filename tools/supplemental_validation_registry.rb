# frozen_string_literal: true
require_relative 'artifact_common'
require_relative '../method/external-validation/validation_helper'
require_relative '../method/validation-strengthening/comparison_policy'
require_relative '../method/validation-strengthening/shape_validation_cases'

# New supplemental checks overlay eligibility without editing archived runs.
# The first four stages describe the original successful validation; a later
# correctness/input/output failure belongs to the external-comparison stage.
class SupplementalValidationRegistry
  STAGES = LocalEvalArtifact::VALIDATION_STAGES.to_h { |stage| [stage, stage != 'output_comparison'] }.freeze
  SHAPE_DEFINITIONS = LocalEvaluation::ShapeValidationCases.definitions
  DEFINITIONS = {
    'floyd-integer-hash-v1' => { 'id' => 'floyd-integer-hash-v1', 'benchmark' => 'floydwarshall',
      'args' => %w[-v -r -n 512], 'comparison' => 'integer_hash', 'timeout' => 30 },
    'stencil-interior-v1' => { 'id' => 'stencil-interior-v1', 'benchmark' => 'stencil3d',
      'args' => %w[-v -r -x 65 -y 61 -z 67 -i 21], 'timeout' => 30 }
  }.merge(SHAPE_DEFINITIONS).freeze
  attr_reader :path, :digest, :data, :records

  def initialize(path)
    @path = File.realpath(path)
    @digest = LocalEvalArtifact.sha256(@path)
    @data = JSON.parse(File.read(@path))
    raise 'Unsupported supplemental registry' unless @data.fetch('schema_version') == 2 && @data.fetch('failed_stage') == 'output_comparison'
    definition = @data.fetch('case')
    raise 'Supplemental case differs' unless definition == DEFINITIONS.fetch(definition.fetch('id'))
    @definition = definition
    authorization = @data.fetch('authorization')
    raise 'Missing supplemental authorization' unless authorization.fetch('source') == 'user' && !authorization.fetch('statement').strip.empty?
    reference = @data.fetch('reference')
    @reference = reference.fetch('stdout')
    raise 'Reference digest differs' unless Digest::SHA256.hexdigest(@reference) == reference.fetch('stdout_sha256')
    raise 'Reference did not pass' unless @reference.include?('Validation: PASSED')
    list = @data.fetch('records')
    @records = list.to_h { |record| [record.fetch('id'), record] }
    raise 'Invalid supplemental IDs' unless list.size == @data.fetch('record_count') && list.size == @records.size && @records.keys == @records.keys.sort
    @records.each { |id, record| verify!(id, record) }
  end

  def reason(id)
    "Output comparison FAILED (#{@definition.fetch('id')}): #{@records.fetch(id).fetch('result').fetch('comparison').last}"
  end

  def verify!(id, record)
    benchmark = @definition.fetch('benchmark')
    identity = id.match(/\A#{Regexp.escape(benchmark)}_.+_(omp|cuda|mpi|hybrid)_r[1-5]\z/)
    unless identity &&
        record.fetch('source_commit').match?(/\A[0-9a-f]{40}\z/) &&
        record.fetch('source_path').match?(%r{\A\d{8}-\d{6}/#{Regexp.escape(id)}\z}) && record.fetch('stages') == STAGES
      raise "Supplemental identity/stages differ: #{id}"
    end
    if SHAPE_DEFINITIONS.key?(@definition.fetch('id')) &&
        !LocalEvaluation::ShapeValidationCases.for_backend(benchmark, identity[1]).include?(@definition)
      raise "Supplemental case uses the wrong backend: #{id}"
    end
    result = record.fetch('result')
    %w[id source_commit source_path].each { |field| raise 'Result identity differs' unless result.fetch(field) == record.fetch(field) }
    raise 'Case identity differs' unless record.fetch('case_id') == @definition.fetch('id') && result.fetch('definition') == @definition
    raise 'Not a failed supplemental check' unless result.fetch('passed') == false && result.fetch('performance_measurement') == false
    raise 'Result digest differs' unless Digest::SHA256.hexdigest(JSON.pretty_generate(result) + "\n") == record.fetch('result_sha256')
    output = record.fetch('stdout')
    raise 'Output digest differs' unless Digest::SHA256.hexdigest(output) == result.fetch('output_sha256')
    raise 'Reference binding differs' unless result.fetch('reference_sha256') == Digest::SHA256.hexdigest(@reference)
    comparison = if result['execution'] && !result.dig('execution', 'success')
      [false, "Supplemental correctness execution failed: exit #{result.dig('execution', 'exit_code')}, timeout #{result.dig('execution', 'timed_out')}."]
    elsif !result.fetch('internal_validation')
      [false, 'Supplemental internal check failed.']
    else
      raise 'Claimed internal pass absent' unless output.include?('Validation: PASSED') && !output.include?('Validation: FAILED') && !output.include?('Validation fail')
      numerical = validate(@reference, output, benchmark)
      numerical.first && @definition['comparison'] == 'integer_hash' ? LocalEvaluation::ComparisonPolicy.integer_hashes(@reference, output) : numerical
    end
    raise "Supplemental failure does not reproduce: #{id}" unless comparison.first == false && comparison == result.fetch('comparison')
  end
end
