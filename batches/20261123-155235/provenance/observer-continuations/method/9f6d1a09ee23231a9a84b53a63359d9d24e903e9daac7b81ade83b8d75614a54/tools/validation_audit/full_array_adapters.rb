# frozen_string_literal: true
require 'digest'

module ValidationAudit
  module FullArrayAdapters
    CANONICAL_HELPER = '39dce5caf66268985c8ea44e5c60b619f1cca6e663a0fec4ff9c1dea9cc43e5e'
    CANONICAL = {
      '_Z13print_resultsIdEvRKSt6vectorIT_SaIS1_EEPKc' => ['f64le', 8],
      '_Z13print_resultsIfEvRKSt6vectorIT_SaIS1_EEPKc' => ['f32le', 4],
      '_Z17print_results_intIjEvRKSt6vectorIT_SaIS1_EEPKc' => ['u32le', 4],
      '_Z17print_results_intIiEvRKSt6vectorIT_SaIS1_EEPKc' => ['i32le', 4]
    }.freeze
    # All six noncanonical helpers were compared with the frozen helper. These
    # changes preserve numerical output/hash semantics. Custom allocators are
    # stateless; the two span calling conventions were checked in bound ELF code.
    HELPERS = {
      'a39089ffebed52641ff91f69e6d56e8954f0021e0396fb13681ddcb8bfe9fef9' => {
        '_Z13print_resultsId15PinnedAllocatorIdEEvRKSt6vectorIT_T0_EPKc' => 'vector' },
      '27d576de6db46d1076977b24de19b79ee1476b5fd66a493c47587e5a723afac6' => {
        '_Z13print_resultsId14FieldAllocatorIdEEvRKSt6vectorIT_T0_EPKc' => 'vector',
        '_Z13print_resultsId22UninitializedAllocatorIdEEvRKSt6vectorIT_T0_EPKc' => 'vector',
        '_Z13print_resultsId13GridAllocatorIdEEvRKSt6vectorIT_T0_EPKc' => 'vector' },
      '4b6b08e1eb09d41dcdb67ca8b515bd084c4026fba4de1d03c8121ec013ec4eb2' => {
        '_Z13print_resultsId13GridAllocatorIdEEvRKSt6vectorIT_T0_EPKc' => 'vector' },
      '7170e8d3eb53d59fc4a612b3ac2f40f901add8893bf36f51aa0525af3677230d' => {
        '_Z13print_resultsIdEvSt4spanIKT_Lm18446744073709551615EEPKc' => 'span_value' },
      '3082da0cb830c94bd4576d86bf84504517d5ad3cd91769ca24e13a7536ccee31' => {
        '_Z13print_resultsISt4spanIKdLm18446744073709551615EEEvRKT_PKc' => 'span_reference' },
      '851d66416ad9bc180c8b7e182f86e20ea042ad59bb4a94d4e99b6dbb4b256bb8' => {
        '_Z13print_resultsIdEvRKSt6vectorIT_SaIS1_EEPKc' => 'vector' }
    }.freeze
    # Offsets are valid ONLY for the exact previously source-bound executables.
    # Each inlined contiguous capture stops once before the original FNV loop.
    BINARIES = {
      '46e0ccd87f6a82fe1a18464d196414e0a1fb4b7f131297d2eea48bb0e6b3b6b2' => {
        'location' => 'main+0xb3c', 'abi' => 'register_bounds', 'start_register' => 'r8',
        'end_register' => 'rcx', 'name' => 'OptionPrices', 'instruction_hex' => '48be25232284e49cf2cb' },
      '81da742def789e7966350550103cdc8fb3bd8f2c2dbd24f333ac66ef8d4900ee' => {
        'location' => 'main+0xf90', 'abi' => 'register_bounds', 'start_register' => 'rdx',
        'end_register' => 'rax', 'name' => 'OptionPrices', 'instruction_hex' => '48b9b301000000010000' },
      '21a066fed7f3116d115ed5b35aa119170d9044203f5fbf4931f585838f00f983' => {
        'location' => 'main+0x1a84', 'abi' => 'register_bounds', 'start_register' => 'rax',
        'end_register' => 'rcx', 'name' => 'MatrixC', 'instruction_hex' => '48bb25232284e49cf2cb' },
      'a8bf7510b542df058b1ff3cee10d0445b7cd2888a43f6887f3b0e45ebea561cc' => {
        'location' => '_Z16printGridResultsPKdm', 'abi' => 'pointer_count', 'name' => 'Grid' },
      '7a701bf2300e9cbe90551ffd5d4c1f9ea41dbb75d5495ab3ef9a36eeabeb79e1' => {
        'location' => 'main+0x14f2', 'abi' => 'frame_vector', 'frame_offset' => -0x130,
        'name' => 'GridSlab', 'instruction_hex' => '440fb6ad0dffffff',
        'assembly' => 'stencil_fixed_faces_and_rank_slabs' },
      '82bcac98d064d0427fb90ffd229fc4a03796fa39fd329e38c40e9173366f1873' => {
        'location' => '_Z23printDistributedResultsRKSt6vectorIdSaIdEEmii',
        'abi' => 'vector', 'name' => 'OptionPricesBlock', 'instruction_hex' => 'f30f1efa',
        'assembly' => 'black_scholes_contiguous_rank_blocks' },
      '1c347e084b6c9f2ba1a11e8e1b5fab659d4d26a2915184c817576e3b4efdbf24' => {
        'location' => 'main+0xc45', 'abi' => 'frame_vector', 'frame_offset' => -0xf0,
        'name' => 'GridSlabWithHalos', 'instruction_hex' => '4c8badb0fdffff',
        'assembly' => 'stencil_rank_slabs_with_halos' },
      '4924109e91d77d89df39a93eaf034d2ea2cff368fcc8a9545e5d98b9be88aec6' => {
        'location' => '_Z14collectResultsiimmPKdP14ResultsSummaryRSt5arrayIdLm10EE',
        'abi' => 'register_count', 'start_register' => 'r8', 'count_register' => 'rdx',
        'name' => 'OptionPricesBlock', 'instruction_hex' => 'f30f1efa',
        'assembly' => 'black_scholes_hybrid_rank_blocks' }
    }.freeze
    # nvcc embeds its process ID in a non-allocated .strtab FILE symbol. For
    # this inspected ELF only, normalize those eight ASCII hex digits in a
    # memory copy used for identity lookup. Every other byte remains pinned,
    # including ELF headers, all loaded CPU/GPU code, data and symbol locations.
    # The actual executable is never modified; its raw digest remains recorded.
    NVCC_TEMPFILE_IDENTITIES = {
      '4924109e91d77d89df39a93eaf034d2ea2cff368fcc8a9545e5d98b9be88aec6' => {
        'bytes' => 1045688, 'filename_offset' => 849611,
        'prefix' => 'tmpxft_', 'suffix' => "_00000000-6_black_scholes.cudafe1.cpp\0",
        'normalized_sha256' => '4d59f842a895dfb077e94aa68e8215b1573c2e5aff527937840942f62d8b55e9' }
    }.freeze
    module_function

    def normalized_nvcc_pid_digest(bytes, profile)
      return nil unless bytes.bytesize == profile.fetch('bytes')
      offset, prefix, suffix = profile.values_at('filename_offset', 'prefix', 'suffix')
      name = bytes.byteslice(offset, prefix.bytesize + 8 + suffix.bytesize)
      return nil unless name && name.match?(/\A#{Regexp.escape(prefix)}[0-9a-f]{8}#{Regexp.escape(suffix)}\z/)
      normalized = bytes.dup
      normalized[offset + prefix.bytesize, 8] = '00000000'
      Digest::SHA256.hexdigest(normalized)
    end

    def rebuilt_binary_spec(binding)
      path = binding['executable']
      return nil unless path && File.file?(path)
      NVCC_TEMPFILE_IDENTITIES.each do |canonical, profile|
        next unless File.size(path) == profile.fetch('bytes')
        bytes = File.binread(path)
        raise 'Observer executable binding changed' unless Digest::SHA256.hexdigest(bytes) == binding.fetch('binary_sha256')
        next unless normalized_nvcc_pid_digest(bytes, profile) == profile.fetch('normalized_sha256')
        return BINARIES.fetch(canonical).merge('binary_identity' => {
          'canonical_binary_sha256' => canonical, 'normalized_sha256' => profile.fetch('normalized_sha256'),
          'nvcc_temporary_symbol_pid_offset' => profile.fetch('filename_offset') + profile.fetch('prefix').bytesize,
          'normalized_bytes' => 8, 'executable_file_changes' => 0 })
      end
      nil
    end

    def entries(binding, symbols, args:)
      helper = binding.dig('source_files', 'common/results_output.hpp', 'sha256')
      special = BINARIES[binding.fetch('binary_sha256')] || rebuilt_binary_spec(binding)
      if special
        raise 'Special observer helper changed' unless helper == CANONICAL_HELPER
        if special['assembly']
          inspected_args = case special.fetch('assembly')
          when 'stencil_fixed_faces_and_rank_slabs', 'stencil_rank_slabs_with_halos'
            %w[-v -r -x 65 -y 61 -z 67 -i 21]
          when 'black_scholes_contiguous_rank_blocks', 'black_scholes_hybrid_rank_blocks'
            %w[-v -r -n 10003]
          else raise 'Unknown streamed adapter'
          end
          raise 'Streamed adapter only covers its inspected pilot shape' unless args == inspected_args
        end
        return [special.merge('dtype' => 'f64le', 'width' => 8)]
      end
      selected = if helper == CANONICAL_HELPER
        symbols.filter_map do |symbol|
          dtype, width = CANONICAL[symbol]
          { 'location' => symbol, 'abi' => 'vector', 'dtype' => dtype, 'width' => width } if dtype
        end
      else
        allowed = HELPERS.fetch(helper) { raise 'Unreviewed result helper' }
        symbols.filter_map do |symbol|
          abi = allowed[symbol]
          { 'location' => symbol, 'abi' => abi, 'dtype' => 'f64le', 'width' => 8 } if abi
        end
      end
      raise 'No supported exact result boundary' if selected.empty?
      selected
    end
  end
end
