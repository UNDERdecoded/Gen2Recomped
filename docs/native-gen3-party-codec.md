# Native GBA party codec

The generic link codec serialized only DVs/stat experience. Native GBA mons
lost their personality, IVs, EVs, nature, ability slot and secret trainer ID.
A clean #215 negative control loses all six fields and changes the example's
HP maximum from 92 to 67. The failing report is retained in private QA output.

`Protocol.packMon`/`unpackMon` now dispatch GBA games to a separate versioned
codec. It carries six-stat IV/EV data and PID, rebuilds native stats/nature and
gender, preserves the selected valid ability slot independently of PID parity,
and retains original-trainer identity (including both host secret-ID aliases),
PP-Ups, current PP, held item, ball, friendship, contest/origin data, ribbons,
markings, language, Pokerus and extension namespaces. Names use native character
limits without splitting UTF-8. Incoming stats are recomputed, never trusted.
Auto-level rebuilds experience/stats and heals status/HP while keeping genotype.
Native toxic identity and sleep counts survive ordinary party transport.

The live path retains both `gender.roll` entry points, at pack and unpack,
including delegated, forced, invalid-result fallback and metadata-steering
policies. Standalone tools without a mounted species registry omit the sender's
derived gender; the decoder still derives it from authoritative data/PID.
Gen1 is an unchanged read-only reference. Comparison maps species/move IDs,
stat-key schemas and gender codes; it retains all compared observations and
callback calls. This does not assert cross-engine network packet compatibility.

Both hellos advertise native party revision 1. Different/missing native codecs
are refused before party exchange in either trade or battle roles. GBA full
fingerprints include `[native_gba_party]1`; cache keys include its revision.
The raw fixture digest changes from #215's `3a76cc5fce47a5c3` to
`2fd444270c3d90db`. This was independently audited by feeding the additional
surface token to the unchanged #215 hasher. Other games' digests remain unchanged;
no golden is reblessed. Active/bench state components include native genotype.

## Reproduce

Use maintained LuaJIT `a4c064539ea931274d407e1249b4bb575424a0f4`:

```sh
luajit tests/engine/gen3_party_codec.lua
luajit tests/engine/gen3_party_transport.lua
luajit tests/engine/gen3_battle_protocol.lua
bash scripts/test.sh --quick
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference \
  --lua /path/to/pinned/luajit --report /tmp/party-codec-report.json
```

The shared fixture calls actual `packMon3`/`unpackMon3` on unchanged Gen1
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, and the actual Gen2 codec. It covers
all 25 natures; levels 1, 35 and 100, ordinary/forced levels; two native species
including Shedinja; alternate and single abilities; zero/max/mixed investments;
canonical/raw/translated registries; original-trainer and other native metadata.
It retains full normalized stats/identity/metadata and both public gender calls.

Host transport checks exercise strict malformed-packet refusal, JSON/save
round trips, actual two-role trade negotiation/application, and complete seeded
link mirrors with nonzero IV/EVs and distinct PIDs/ability slots. Genotype is
checked against the original sender, not only against the other equally rebuilt
peer. Every completed paired turn hash and state component is compared.

A CPU-only private smoke also round-trips actual locally imported FireRed and
Emerald Poliwag data, comparing all IVs/EVs/stats, selected ability, secret ID,
current PP and public API-3 `TOX`/personality reads. No ROM/assets/saves are
published. This is imported-record acceptance, not a live UI/full playthrough.

Full native egg-legality checks, other-generation codecs, timed side/volatile
producers, whole-game RNG/VBlank scheduling and demo controller playback remain
separate work. This codec does not certify those lifecycles.
