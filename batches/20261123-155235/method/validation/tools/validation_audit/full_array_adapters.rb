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
    # All listed noncanonical helpers were compared with the frozen helper. These
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
        '_Z13print_resultsIdEvRKSt6vectorIT_SaIS1_EEPKc' => 'vector' },
      'ad23508512c2dfa8215a515462b259c9b2bd695b00e101cd5a62a44e4cbb9d4e' => {
        '_Z13print_resultsIdEvPKT_mPKc' => 'pointer_count' },
      '581dcf7f5071b2b3247520fc4100fa21303b1b41a31896219e48d54105603b00' => {
        '_Z13print_resultsIdEvSt4spanIKT_Lm18446744073709551615EEPKc' => 'span_value' },
      '03f8fe8c98f7ed1d40da3fdda67893189c7900001ddc03116a514a01f8f19076' => {
        '_Z13print_resultsIdEvSt4spanIKT_Lm18446744073709551615EEPKc' => 'span_value' },
      'd4922d91a839b996479060b7e6569d24ab171d8d6af5314de652bd592c385269' => {
        '_Z13print_resultsIdEvPKT_mPKc' => 'pointer_count' },
      '2977796cef2f4daa6d61fa8fdb34465057edbcb2230460e319b1299dae6296b0' => {
        '_Z13print_resultsIdEvPKT_mPKc' => 'pointer_count' }
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
        'assembly' => 'black_scholes_hybrid_rank_blocks' },
      'b0025eff23674c676c830864778aa22465b1cca6a1542ba27f1724d34374e92d' => {
        'location' => '_Z12runBenchmarkiPPcii+0x2e8', 'abi' => 'frame_pointer_count',
        'start_frame_offset' => -0x1b8, 'count_frame_offset' => -0x1b0,
        'name' => 'OptionPricesBlock', 'instruction_hex' => '4585ff',
        'helper_sha256' => '04ba52fc14d3d9c01d656977b574e26e9633b1f4bc2d7b7a22a3ad15e0b0fce5',
        'assembly' => 'black_scholes_contiguous_rank_blocks' },
      '51d45668ef725bf440bac2882f134bfaa461c9fd88c155d83445dd220b9f245c' => {
        'location' => '_Z12runBenchmarkiPPcii+0x718', 'abi' => 'register_bounds',
        'start_register' => 'rax', 'end_register' => 'r8',
        'name' => 'OptionPricesBlock', 'instruction_hex' => '4929c0',
        'helper_sha256' => '3df0d8f3b458d61118212699fdf1199e7f7d9ee2b749ef0874a841e53dafa16e',
        'assembly' => 'black_scholes_contiguous_rank_blocks' },
      '5b471ff955d3c774a1adc312adad47f0b6aa68b7bad2b5208047920dd16f44ed' => {
        'location' => '_ZN12_GLOBAL__N_112runBenchmarkEiPPc+0x1f55', 'abi' => 'register_count',
        'start_register' => 'rbx', 'count_register' => 'rax', 'name' => 'CholeskyRowStripe',
        'instruction_hex' => 'c5fb109598fcffff', 'assembly' => 'cholesky_root_row_stripes' },
      'dc81d125d0757eb30e806f30a1fe2ea22e5ec67f93f1e4d270c2acfd111fc5ff' => {
        'location' => '_Z12printResultsPKdRK7OptionsiiP19ompi_communicator_t+0x2ee',
        'abi' => 'register_count', 'start_register' => 'r12', 'count_register' => 'r11',
        'name' => 'GridOutputBlock', 'instruction_hex' => '49b8b301000000010000',
        'assembly' => 'stencil_root_output_blocks' },
      '3852a7656f9bebb362f08e15fa4beafd1548b0bf476756cac02a02883b4fda25' => {
        'location' => '_Z23printDistributedResultsRK5WorldiPKiiP19ompi_communicator_t+0x5d9',
        'abi' => 'register_count', 'start_register' => 'r10', 'count_register' => 'rdx',
        'name' => 'EnergyRowSegment', 'instruction_hex' => '4c89d1',
        'assembly' => 'unstructured_root_row_segments' }
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
        'normalized_sha256' => '4d59f842a895dfb077e94aa68e8215b1573c2e5aff527937840942f62d8b55e9' },
      'dc81d125d0757eb30e806f30a1fe2ea22e5ec67f93f1e4d270c2acfd111fc5ff' => {
        'bytes' => 71072, 'filename_offset' => 64931,
        'prefix' => 'tmpxft_', 'suffix' => "_00000000-6_stencil3d.cudafe1.cpp\0",
        'normalized_sha256' => '55a95e4738bdd94fde14e3801233623e358bfa80d38f267149fc3d52cd110964' }
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
        raise 'Special observer helper changed' unless helper == special.fetch('helper_sha256', CANONICAL_HELPER)
        if special['assembly']
          inspected_args = case special.fetch('assembly')
          when 'stencil_fixed_faces_and_rank_slabs', 'stencil_rank_slabs_with_halos', 'stencil_root_output_blocks'
            %w[-v -r -x 65 -y 61 -z 67 -i 21]
          when 'black_scholes_contiguous_rank_blocks', 'black_scholes_hybrid_rank_blocks'
            %w[-v -r -n 10003]
          when 'cholesky_root_row_stripes'
            %w[-v -r -n 513]
          when 'unstructured_root_row_segments'
            %w[-v -r -n 33 -i 513]
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
