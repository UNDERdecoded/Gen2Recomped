# External compatibility fixtures

This directory contains an owned synthetic dataset, a loader probe, public
callback names and SHA-256 digests. It contains no reference implementation or
package source. The probe reads unchanged packages from a caller-supplied,
read-only checkout at the commit in `index.json`.

Run from the repository root:

```
python3 tools/check_external_mod_fixtures.py --reference /absolute/reference \
  --lua /absolute/luajit --report .local/qa/mod-fixtures/report.json
```

The optional local Python runner requires the QA storage guard and its companion
modules. Supply their directory with `--qa-tools` when they are maintained outside
the checkout. It never falls back to unguarded local execution.

The command authenticates every file before loading it. It also checks that the
eight shipped gallery packages match the external package bytes. Each package
gets an isolated worker running the production Loader, manifest validation,
registry merge and callback registration. The synthetic pack filesystem and CPU
image objects exercise entrypoints without providing cartridge art or claiming
rendered-image correctness. Writes stay in the worker's memory.

A missing package, changed file, unknown hook, unloaded entrypoint or worker
failure makes the gate fail. The initial probe deliberately fails on
`mystery_dungeon_follower` at `src.import.pmd.Sprite`; retain that failed report as
the negative control. This is an executable compatibility gap, not a skipped or
successful test. After aliases are available, the requested intermediate
acceptance may name unsupported modules explicitly; complete acceptance requires
all entrypoints to load. ROM extraction is outside this gate.

The gallery test additionally uses the synthetic dataset whenever no imported
cache is present, so `tests/mod_examples_tests.lua` runs its original effect and
hook assertions in a ROM-free checkout. It validates the legacy API-1 manifest
separately from the retired production example path. No compatibility fixtures
are placed under `mods/`.

Use `--phase aliases` only for the explicitly defined intermediate acceptance: the
one sprite-interface gap must be reported with its module and affected consumer.
It is recorded as an expected gap, never as a loaded mod. Default complete
acceptance remains red until the entrypoint actually loads.
