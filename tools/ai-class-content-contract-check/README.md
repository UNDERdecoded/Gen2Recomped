# Shared AI-class content contracts

Run the same public metadata consumer through both real SDK loaders. The
Gen1Recomp reference must be clean at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

```sh
python3 tools/ai-class-content-contract-check/check.py --gen1 /path/to/pinned/gen1 --host-api 3 --report /tmp/ai-class-api3.json
python3 tools/ai-class-content-contract-check/check.py --gen1 /path/to/pinned/gen1 --host-api 2 --report /tmp/ai-class-api2.json
```

Use `--lua /path/to/luajit` when necessary. Each invocation runs 16 isolated
workers across Red/Blue/Yellow, Gold/Silver/Crystal and FireRed/Emerald,
comparing 56 pairs of observations. Both workers load the same consumer file;
only the version/data fixtures and host SDK mode differ. File hashes and
engine refs are recorded, and the checker refuses a changed reference.

The source always uses API 3; the host uses API 3 or API 2 with explicit unified
content. Gen1Recomp API-2 AI-class reads expose live passthrough records, so
this is not a claim of shared API-2 read-aliasing behavior. API 3 is the common
detached-record contract. Native API-1/2 formats are tested separately by the
host unit suite.

Seven cases cover register, patch, replacement override, optional-item deletion,
brain-record metadata, removal and failed-entry rollback. Observations include
public canonical item IDs and detached write/read/iteration results. Host
assertions also verify that physical imported-style item keys reach the native
registry. Brain function presence is recorded; no brain is executed here.

These are ROM-free synthetic metadata fixtures through real loaders, not native
battle-policy tests. Run `tests/drivers/ai_class_content.lua` separately against
an isolated imported-data installation for title/New Game metadata validation.
See [the API contract](../../docs/portable-ai-class-content.md).
