# Native script-text contract check

Run `python3 tools/text-source-contract-check/check.py --gen1 /clean/gen1 --lua luajit`.
The reference must be clean at the pinned commit. No code is copied into it.
Eight versions each run in separate processes for both real SDKs. The unchanged
public consumer exercises scalar registry operations, rollback, freeze, Gen-2
physical ID routing and a shared source-language corpus, checked against native
storage. Native script/text readers run separately from the corpus.

`--host-api 2` checks the host's opt-in unified mode against reference API 3;
it does not claim the reference supports unified content on API 2.
`--report path.json` records exact observations, references and host dirtiness.
A mismatch or an SDK/test error fails the checker. No ROM, cache or save is needed.
See `docs/api3-text-sources.md` for remaining prose/label bindings.
