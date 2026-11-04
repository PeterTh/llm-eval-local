// Standalone diagnostic. Includes the frozen sequential implementation without
// editing it, then corrupts a completed result solely to test validator coverage.
// This is NOT a generated winner and NOT replacement scientific evidence.
#define main original_program_main
#ifdef FLOYD_PROBE
#include "reference/floydwarshall/floydwarshall.cpp"
#else
#include "reference/stencil3d/stencil3d.cpp"
#endif
#undef main

int main(int argc, char**) {
    const bool mutate = argc > 1;
#ifdef FLOYD_PROBE
    constexpr size_t n = 512;
    std::vector<unsigned int> d(n*n), path(n*n);
    initializeDistanceMatrix(d, n, 1, MAX_DISTANCE);
    initializePathMatrix(path, n);
    floydWarshall(d, path, n);
    const size_t p = 11*n + 12;
    const auto before = d[p];
    const auto after = before == 1 ? 2u : 1u;
    if (mutate) d[p] = after;
    fprintf(stderr, "index=%zu before=%u after=%u changed_elements=%d\n", p, before,
            d[p], mutate ? 1 : 0);
    print_results_int(d, "DistanceMatrix");
    const bool valid = validateResult(d, n);
#else
    constexpr size_t n = 64;
    std::vector<Real> a(n*n*n), b(n*n*n);
    initializeGrid(a, n, n, n);
    for (int i=0; i<20; ++i) { stencilIteration(a,b,n,n,n); a.swap(b); }
    const size_t p = idx3(1,1,1,n,n), q = idx3(2,1,1,n,n);
    const auto before = a[p];
    if (mutate) std::swap(a[p],a[q]);
    fprintf(stderr, "index=%zu other_index=%zu before=%.17g after=%.17g changed_elements=%d max_abs_error=%.17g\n",
            p,q,before,a[p],mutate ? 2 : 0,std::abs(a[p]-before));
    print_results(a, "Grid");
    const bool valid = validateResult(a,n,n,n);
#endif
    printf("Validation: %s\n", valid ? "PASSED" : "FAILED");
    return valid ? 0 : 1;
}
