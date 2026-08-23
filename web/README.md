# LLM Autoparallelization Benchmark

Client-only companion site for the extended evaluation paper. The site is a private npm project built with React, strict TypeScript, Vite, Vega-Lite, Zod, Vitest, and Playwright. It is designed for the `llm-eval-local` GitHub Pages project path and has no runtime service, CDN dependency, cookies, or authentication.

## Repository boundary

Everything expected to change during normal website development lives below `web/`. Generated payloads, `dist/`, `node_modules/`, browser reports, and review screenshots are ignored. The root artifact tooling explicitly excludes this directory and the stable Pages workflow from scientific checksums, retention checks, exports, and size budgets.

The only root integration files are:

- `.github/workflows/web.yml`, which delegates build and test behavior to this directory;
- `.github/workflows/verify.yml`, whose path filters skip website-only updates;
- `tools/artifact_common.rb` and the one-time regenerated root checksum entries.

## Local development

Use Node 24 as recorded in `.nvmrc`.

```sh
npm ci
npm run dev
```

The development command regenerates deterministic static data before starting Vite. Useful validation commands are:

```sh
npm run check
npm run build
npm run test:e2e
```

`npm run check` runs the generator, strict type checking, unit/component tests, and a two-pass deterministic-output check. `npm run test:e2e` builds the production bundle, starts a local static server, and tests desktop and narrow-mobile layouts with Playwright-managed Chromium.

## Generated data

`scripts/build-data.ts` reads the canonical parent artifact without modifying it. It validates score bounds, duplicate and missing joins, success/metric consistency, reviewed thresholds, provenance, and the five canonical millisecond measurements for successful benchmarks. It emits content-hashed files under `public/data/` plus a generated manifest pointer under `src/generated/`:

- one manifest containing dataset identity, score bands, entities, cells, thresholds, and asset locations;
- one compact score-count cube loaded by analytical overview pages;
- one run index used for direct result URLs;
- one lazily loaded run shard for each observed benchmark/backend cell.

Entity IDs are arbitrary strings. Existing presentation labels and backend order are optional overrides in `config/site.json`; an unseen ID is displayed verbatim.

## Routes and filter state

The site uses Pages-safe hash routes. Model, benchmark, backend, tier, outcome, sorting, and view-specific state are encoded as query parameters, so browser history and copied URLs restore the view. Cross-view navigation preserves only the shared model, benchmark, and backend filters; run-specific filters remain scoped to the Runs view and its detail return path.

## Deployment

Pull requests build and test without publishing. Updates to `web/` or `data/` on `main` run the same validation and upload `web/dist` through GitHub's artifact-based Pages workflow. The repository's Pages source must be set once to **GitHub Actions**.

Every coherent build proposed as final for a development step is held for visual review before that step is accepted. Do not publish or treat a review build as accepted merely because automation passes.

## First implementation step

The accepted first implementation step includes Tiered Success, the full Runs table, individual result provenance/detail, methodology, and citation information. Model Scores, Complexity, and Performance remain deliberately staged for later implementation steps.
