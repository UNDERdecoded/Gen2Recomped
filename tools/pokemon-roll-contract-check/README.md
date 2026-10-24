# Shared native Pokemon identity contracts

Use a clean Gen1Recomp checkout pinned at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`:

```sh
python3 tools/pokemon-roll-contract-check/check.py --gen1 /path/to/gen1 --api 3 --format unified --report /tmp/identity.json
```

Run API 1/native, API 2/native, API 2/unified and API 3/unified. Each mode
starts 12 isolated workers across Red, Gold, Silver, Crystal, FireRed and
Emerald. Reference API 2 remains native; host API-2/unified is compared with
that native behavior. API 3 is the common unified callback boundary.

The unchanged public consumer exercises actual Gen-2 Mon.new, identity
refresh and breeding queries and GBA Party.giveMon/Pokemon predicates.
The host uses imported-style species keys. No producer is replaced with a
Runtime.call stub. Cases cover overrides, delegation, nil/truthy/invalid
returns, DV/PID steering and replacement, IV isolation, threshold scope and
fallback timing, failure before/after next, entry rollback, native forced
values, cached birth gender, retirement and query RNG/identity preservation.

The Gold worker additionally records all 65,536 native ratio/attack/speed
outcomes as an exact ordered string. Both engines' strings must match;
counts/checksum alone do not decide parity. Red verifies unavailable hooks.
The tests are ROM-free. Imported Gold/FireRed/Emerald UI/forced-wild tests
are separate native driver checks; no full playthrough or pixel equality is
implied.
