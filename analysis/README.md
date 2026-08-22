# Analysis

Analysis must read only the versioned files under `data/`. Put reusable source in
`src/`, optional output-stripped notebooks in `notebooks/`, final machine-readable
tables in `tables/`, and final figures in `figures/`.

Commit the dependency/environment lockfile for the selected analysis stack. Do not
commit notebook cell output, caches, serialized interpreter workspaces, or intermediate
datasets. Prefer CSV for tables and SVG or PDF for vector figures; retain one canonical
format unless the publication toolchain requires another.

Every completed analysis should document the Git data release/tag it consumed and
provide one command that rebuilds its tables and figures.
