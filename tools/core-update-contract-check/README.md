# Cross-engine core.update contract

```sh
python3 tools/core-update-contract-check/check.py --gen1 /path/to/gen1recomp --lua luajit --report /tmp/core-update.json
```

Gen1 must be clean at `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Both native
loaders execute `examples/portable_core_update/main.lua` unchanged. The tests
invoke each engine's actual love.update callback loaded from main.lua, with a
Game:update spy and fixtures for non-game owners supplied through test-only
upvalue injection. Neither native main.lua nor PlatformHooks is replaced.
Gen2's unrelated walker bookkeeping and Gen1's HostDisplay backend use a
counter so the test does not depend on external services.

The checker covers Red, Gold, FireRed and Emerald, asserts forwarding, pause,
priority, argument replacement, errors, unsubscribe and host/driver routing,
then compares frame journals. `--format unified` selects unified API 2;
`--api 3 --format unified` selects API 3. `--gen2` selects an integration
checkout. No ROM, native window or renderer is needed, and no Gen1 source is
written.
