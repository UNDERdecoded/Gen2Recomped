# Cross-engine input hook contract

Run `python3 tools/input-hook-contract-check/check.py --gen1 /path/to/gen1recomp
--lua luajit --report /tmp/input-contract.json` from Gen2Recomped.

The Gen1 checkout must be clean at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Both native loaders execute
`examples/portable_input/main.lua` unchanged, against the real Input singleton
and native Game/Game2/Game3 callbacks. Four host versions run in separate
processes. Each run asserts the contract and the checker compares resulting
held-state journals. No ROM or window is needed, and Gen1 is never patched.

Use `--format unified` for API-2 callback-format integration and
`--api 3 --format unified` for the common API-3 entry. These modes require the
corresponding host features; unsupported manifests fail rather than being
silently downgraded. `--gen2` selects a separate integration checkout.
