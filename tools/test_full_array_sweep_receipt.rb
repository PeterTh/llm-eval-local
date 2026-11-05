# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'full_array_sweep_receipt'
require_relative 'external_validation_overlay'

class FullArraySweepReceiptTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  RECEIPT = 'validation-supplements/20261105-full-array-full/export.json'
  Reader = Struct.new(:root) do
    def path(relative) = File.join(root, relative)
  end

  def test_complete_real_sweep_has_one_verified_eligibility_view_for_every_benchmark
    reader = Reader.new(ROOT)
    digest = LocalEvalArtifact.sha256(reader.path(RECEIPT))
    verifier_definition = defined?(ValidationAudit::FullArrayFullVerification)
    sweep = FullArraySweepReceipt.new(reader, RECEIPT, digest)
    assert_equal [verifier_definition], [defined?(ValidationAudit::FullArrayFullVerification)]
    receipt = JSON.parse(File.read(reader.path(RECEIPT)))
    assert_equal 6747, receipt.fetch('population')
    assert_equal 10, sweep.case_configurations.size
    assert_equal receipt.fetch('failed_ids'), sweep.case_configurations.values.flat_map { |config| config.fetch('applied_ids') }.sort
    assert sweep.inputs.key?('validation-supplements/20261104-full-array-pilot/export.json')
    configuration = sweep.case_configurations.fetch('roomsim')
    registry = FullArrayValidationRegistry.new(configuration, sweep)
    assert_equal 94, registry.records.size
    assert_match(/Output comparison FAILED/, registry.reason('roomsim_gpt-5.6-sol-xhigh_hybrid_r3'))
    assert_raises(RuntimeError) { sweep.verify_configuration!(configuration.merge('applied_ids' => [])) }
    assert_raises(RuntimeError) { FullArrayValidationRegistry.new(configuration, nil) }
  end

  def test_wrong_receipt_digest_is_rejected_before_loading_any_verifier
    error = assert_raises(RuntimeError) { FullArraySweepReceipt.new(Reader.new(ROOT), RECEIPT, '0' * 64) }
    assert_match(/receipt digest differs/, error.message)
  end

  def test_member_bytes_are_pinned_before_loading_bundled_code
    Dir.mktmpdir('full-array-receipt-test-', '/tmp') do |root|
      relative = 'sweep/verification-method/tools/validation_audit/verify_full_array_full_export.rb'
      path = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'raise "Unverified code must not load"')
      receipt_path = File.join(root, 'sweep/export.json')
      File.write(receipt_path, JSON.generate('schema_version' => 1, 'kind' => 'full-array-correctness-sweep',
        'files_sha256' => { relative.delete_prefix('sweep/') => '0' * 64 }))
      error = assert_raises(RuntimeError) do
        FullArraySweepReceipt.new(Reader.new(root), 'sweep/export.json', LocalEvalArtifact.sha256(receipt_path))
      end
      assert_match(/evidence changed/, error.message)
    end
  end
end
