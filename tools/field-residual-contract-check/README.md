# Native field-residual contract comparison

Run from a complete Gen2Recomped checkout with LuaJIT and Python 3:

```sh
python3 tools/field-residual-contract-check/check.py \
  --gen1 /path/to/gen1 --api 3 --format unified \
  --report /tmp/field-residual-contract.json
```

The clean Gen1Recomp checkout must be at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. It is read only; tests come
from the host checkout and load the same public example entry via each real
SDK. No ROM, cartridge cache, private mod or network access is needed.

The checker runs one isolated worker per engine/version across
Red/Blue/Yellow, Gold/Silver/Crystal and FireRed/Emerald. Use `--api 1 --format
native`, `--api 2 --format native`, `--api 2 --format unified`, and `--api 3
--format unified` for the complete compatibility matrix. API 2 unified uses
the source engine's native callbacks because its SDK has no such opt-in.

Workers execute real native end-of-turn/residual code, including registration
of GBA ordinary residual handlers, rather than calling Runtime manually.
Canonical observations compare public context and descriptor decisions;
ordinary native move damage is measured relative to the callback snapshot.
Gold's full native turn includes an enemy move, whereas GBA's collector
records residual steps without running the full presentation/award controller.
Neither comparison establishes whole-battle rule or pixel equivalence.

Host-only authority tests additionally drain real native EXP/faint/replacement
queues and cover all registered versions and stale state boundaries. JSON
reports record the reference/runtime refs, dirty-worktree status, consumer
hash, observations and assertion totals. They contain no cartridge data.
