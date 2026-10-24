# Native Gen-2 held-definition contracts

Run from the host checkout with Python 3, LuaJIT and a clean pinned Gen1:

```sh
python3 tools/held-content-contract-check/check.py \
  --gen1 /path/to/gen1 --api 3 --format unified --report /tmp/held-content.json
```

The source must be at `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.
Test API 1/native, API 2/native, API 2/unified and API 3/unified. Both SDKs load
an unchanged consumer. The reference API 2 has no unified opt-in; its native
records are compared with both host API-2 formats. API 3 is the common unified
contract. Gold/Silver/Crystal execute native held definitions
through the production merge/write-back and native residual paths. Red,
FireRed and Emerald verify unavailable accessors without manufacturing a
consumer for generations the reference does not support.

Cases include overrides, parameter patches/deletion, tombstones, registered
items with explicit indices, custom effect names, independent item-price
patches, dependency-ordered contributions, detached enumeration, invalid
entries, rollback and a genuine no-mod load. Reports preserve actual native
outcomes, SDK mode, engine refs and dirty status. No ROM or private mod is
needed. The source is read-only; these are not complete playthrough tests.
