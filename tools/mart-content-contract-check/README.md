# Shared native mart contracts

Run the unchanged public consumer through both real SDKs and actual native
mart readers/purchase paths. The source is pinned clean at Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, which introduces the mart registry.
Earlier contract families retain their own reference pins.

```sh
python3 tools/mart-content-contract-check/check.py --gen1 /path/to/pinned/gen1 --api 3 --format unified --report /tmp/marts.json
```

Run API 1/native, API 2/native, API 2/unified and API 3/unified. Reference API 2
has no unified opt-in; host API-2/unified is compared with its native behavior.
Each mode launches 12 isolated workers for Red, Gold, Silver, Crystal, FireRed
and Emerald. Gold/Silver/Crystal compare shelf records and actual purchases;
the other versions check the honest unavailable boundary. This is not a
claim of whole-game or pixel parity. Host fixtures use imported `ITEM_*` keys
while the reference uses common keys. Native imported Gold UI/VM execution
is a separate driver and does not require ROMs in CI.

Cases cover unchanged/no-mod behavior, replacement, empty stock, removal,
registration, ordinary price composition, zero/maximum bargain prices,
ordered overlays, rollback and malformed lists. The scalar DELETE sentinel
is rejected by strict SDK schemas; native API 1 retains its warning path.
