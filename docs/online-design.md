# Online play: audit and design

Status: **built** (uncommitted as of 2026-11-06). Parts 1 to 3 are the design as
written on 2026-11-03 against engine 0.7.6, kept for the reasoning; where the
build differs, **Part 4 "As built"** at the end wins. Players: see
`docs/online-guide.md`.

The goal, in the user's words: an online system for every game's features; a
LINK entry in every game's START menu that works for that game; short codes one
player shares and another enters to battle or trade; a working GTS and other
online features; an MMO-style mode if possible; and no required server, with
players hosting their own worlds and inviting others.

Part 1 audits what exists. Part 2 is the design. Part 3 splits the work into
streams that parallel agents can build without editing the same files.

---

## Part 1. Audit

### 1.1 Transport and protocol (`src/link/`, `src/net/`)

| Module | What it is |
|---|---|
| `Net.lua` (418 lines) | Two backends behind one API (`host/join/send/update/poll`, `.paired/.closed/.error`). **ENet P2P**: `enet.host_create("*:7777", 2 peers, 1 channel)`. The host shows `Net.lanIP()` and the port. The guest types an IPv4 address. Messages are JSON on reliable channel 0. Only one peer is accepted, and a second connect is dropped. **TCP relay**: newline-delimited JSON to `pokeserver` at `147.182.215.255:7778` (`POKEPORT_RELAY_ADDR` overrides it). `{type="host"}` returns `{type="hosted", code}` with a 6-character room code, and `join` returns `paired`, `join_error` (`not_found`/`full`/`expired`) or `peer_gone`. `Net.loopbackPair()` gives two in-memory ends that re-encode through JSON, for tests. |
| `Protocol.lua` | Message vocabulary (`hello`, `records`, `party`, `pick`, `confirm`, `action`, `event`, `bye`). `packMon`/`unpackMon` carry the **Gen 1/2 field set only**: species, level, exp, hp, status, nickname, item, `dvs`, `statExp`, moves (id/pp/ppUps), ot, otId, `extra`. `unpackMon` rebuilds stats with `Stats.calc(def, level, dvs, statExp)`. `TradeSession` is the trade state machine and supports a negotiated "subset" trade. `apply()` handles trade evolutions through `Evolution.pendingFor` and has a `timeCapsule` flag that nothing sets. |
| `Handshake.lua` | Hello v2: protocol, name, engineVersion, apiVersion, `Fingerprint.compute`, mods list, linkModified. Verdicts: `full` (lockstep battle and trade), `subset` (trade restricted to records both sides hash identically, no battle), `vanilla_peer`, and `refused` (different engine major, or a modded client against a v1 peer). `onlineAllowed` requires vanilla play (translations excepted) for the relay modes. **The hello carries no generation, game or family field.** |
| `Fingerprint.lua` | FNV-1a 64-bit digest over an allowlist: species (baseStats, types, baseExp…), moves, statuses, effects, constants, link_fields. It also produces per-record hashes for the subset negotiation. |
| `LinkState.lua` (812 lines) | The LINK screen: `LAN` (host or type an IP), `ONLINE` (relay host with a code, or enter a code), and `TOURNAMENT`. A battle-options level picker (ANY/50/100). The trade UI plays `Gen2TradeAnim` on Gen 2 and Red's `TradeAnim` everywhere else, so **Gen 3/4/5 link trades play the Game Boy animation**, not `Gen4TradeSequence`/`Gen5TradeSequence`. It autosaves after a trade. The screen is drawn at 160×144. Its header comment ("no relay server") is out of date. |
| `LinkBattle.lua` (941 lines) | A lockstep battle. Both sides run `BattleState` on a shared Park-Miller seed and exchange actions plus a per-turn state hash; a desync ends in a draw. `newSpectator` rebuilds a match from relayed traffic, for tournaments. There is no exp, money or badge boost. |
| `Tournament.lua` (652 lines) | Single-elimination bracket on the relay only (`host_tournament` and related messages), with spectating. Vanilla only. |
| `CodeEntry.lua` | A 6-slot d-pad scrub over `23456789ABCDEFGHJKMNPQRSTUVWXYZ`. |
| `TradeText.lua` | Each cartridge's own trade wording (Gen 2 keys mapped to Emerald's). |
| `src/net/Fetch.lua` | An async HTTP download job wrapper for mods. Not used by link play. |
| `src/core/DiscordPresence.lua` | "Ask to Join" passes a relay code into `LinkState.newJoinOnline`. |

The relay server's source is **not in this repository**. It runs as an external
service.

### 1.2 The online mod (`mods/gen2recomped-online`, id `gen2online`)

This is a separate, **unbundled** mod (`scripts/bundled_mods.txt` lists only
DRAMATIC_SHAPE and EMERALD_3DS_VOXEL). It is a port of "Gen1Online" for
**Gold/Silver only**. Its design is the opposite of serverless:

* `gts_server.py` (2,706 lines) is a central HTTP server: GTS deposit, trade,
  withdraw and claim; `sync_pos` overworld presence (polled by HTTP from a
  `love.thread`); chat; PvP challenge rooms (battle messages relayed by
  polling); parties; Hold'em casino tables; 27 quests (IDs 1001–1027);
  accounts and redeem tokens; profanity filter; rate limiting; JSON file
  persistence.
* `main.lua` (4,315 lines) monkey-patches `OverworldState.enter/update`,
  forces the start map, and adds START → CONNECT TO SERVER. `GTS_SERVER_URL`
  is hard-coded to `https://gts.cedricslabs.com`. It needs `ssl.https`, so it
  falls back to plain HTTP where that library is missing.
* `gen2_compat.lua` provides a Gen 2 `packMon` (held item, happiness, pokerus,
  met data, shiny) and same-generation-only GTS and PvP filtering.

Its useful lessons are the feature list (presence, chat, challenge, GTS
filters, parties, quests) and the per-generation wire fields. Its architecture
(HTTP polling against one VPS, monkey-patching) is not one to carry forward.

### 1.3 Per-game matrix

Legend: **Y** works; **P** partial or broken in a way noted; **N** absent;
**stub** means the script answers "no connection".

| Game | LINK in START | Battle | Trade | Wire format today | Same-family pairing | In-game link rooms | GTS |
|---|---|---|---|---|---|---|---|
| Red / Blue / Yellow | **Y** (`StartMenu.lua`, needs a party) | **Y** lockstep (tests pass) | **Y** | Gen 1 fields, complete | R↔B↔Y: subset trade or full battle when fingerprints match | Cable Club receptionist opens LinkState (`OverworldController:cableClubReceptionist`) **Y** | N |
| Gold / Silver / Crystal (+Prism, Polished) | **Y** (same `StartMenu`) | **Y** engine syncs (probe: no desync) | **P**: happiness, pokerus and caught data are not on the wire | Gen 1 shape plus item | G↔S↔C by fingerprint subset | PC 2F receptionists = `g2_unavailable` **stub** (only START reaches link) | N |
| Ruby / Sapphire / Emerald | **Y** (`Gen3StartMenu`, inserted before EXIT) | **P**: runs in sync, but stats are rebuilt Gen 1/2-style (see 1.4) | **P/broken**: personality, IVs, EVs, nature and ability are lost, so stats change and shininess and gender are re-rolled | Gen 1/2 fields | E↔FRLG would be "subset" | Cable Club stairs warp **Y**. `TryBattleLinkup`/`TryTradeLinkup` = LINKUP_FAILED **stub**. Union Room, Wireless and record mixing are **stubs** | N |
| FireRed / LeafGreen | **N**: excluded by `not frlg` (`Gen3StartMenu.lua:293`, commit bbba9d5, the FRLG menu layout pass) | (reachable only by no route) | same as Emerald | same | — | stub as Emerald (`Gen3SpecialsFRLG.lua:543`) | N |
| Platinum | **N**: `Gen4StartMenu` has a MODS row only | **P** engine syncs (probe) | **P/broken**: also loses `form` | Gen 1/2 fields | Pt↔HGSS "subset" | Wi-Fi gates, `trystartgtsapp`, Union Room greeting editor, `checkhaswifilistvalidlogin` = `g4_no_feature` **stub** (`PtMiscCommands.lua:426-430`, `Gen4ScriptVM.lua:1649`) | N (Global Terminal GTS **stub**) |
| HeartGold / SoulSilver | **N** (`HgssStartMenu` inherits Pt rows, plus MODS) | **P** | **P/broken** | same | Pt↔HGSS | Union Room (HGSS coverage notes list M0957 as the main uncovered area), Wi-Fi Club **stub** | N (Goldenrod GTS **stub**) |
| Black / White | **N** (`Gen5StartMenu` grid, plus a MODS tab) | **P** | **P/broken** | same | B↔W | Wireless and Wi-Fi functions answer "no partner" (`Gen5BattleSubway.lua`, `Gen5MiscFieldOps.lua` 0x139) **stub** | N (Driftveil GTS **stub**) |

Cross-generation rules: **none exist**. Nothing in the hello names a
generation. Cross-game pairing is decided only by record hashes:
`Protocol.eligibleParty` greys out any mon whose species or move record hash
differs. In practice this means:

* Gen 1↔Gen 2 baseStats differ (Special was split), so every mon reads as
  "different data". No Time Capsule is possible.
* Gen 3 and later use different species keys (Emerald uses names; Gen 4/5 use
  dex numbers), so mixed pairs share nothing.

**Pal Park (Gen 3→4) and Poké Transfer (Gen 4→5) already exist** as offline
one-way features (`src/world/Gen4PalPark.lua`, `src/world/Gen5PokeTransfer.lua`,
`src/pokemon/CrossGen.lua`). They read the other game's save and cache on the
same install.

### 1.4 Verified by running

* `POKEPORT_DATA_DIR=G:/Gen2Recomped/data/generated python tools/run_lua_check.py tests/run_link_tests.lua`
  printed **ALL LINK TESTS PASSED** (78 core checks, and mod link 174/174).
  The run uses the Red cache. The test file needs `POKEPORT_DATA_DIR`, because
  the repo checkout has no `data/generated`.
* Scratch probe `G:/Gen2Recomped/scratch_claude/online/roundtrip.lua` (pack,
  then unpack, on each cache):
  * Emerald, FireRed, Platinum, HeartGold and Black lose
    `personality, ivs, evs, nature, abilitySlot` (and `form` on Gen 4). The
    rebuilt stats differ: Platinum Bulbasaur Lv30 HP went from 70 to 68 and
    SpA from 48 to 44.
  * Crystal survives apart from `catchRate`. The probe's fresh mon carries no
    happiness or pokerus, so those Gen 2 losses come from reading `packMon`,
    not from the probe.
* Scratch probe `battle_probe.lua` ran a loopback lockstep battle on the
  Crystal, Emerald, Platinum and Black caches. Both sides construct, and they
  advance 5 to 10 turns with identical per-turn hashes (no desync). The
  harness never finished a battle, because mashing A re-selects a move with 0
  PP ("No PP left for this move!"). That is a harness artefact, not an engine
  stall. Finishing a Gen 3/4/5 battle end to end is still unverified.

### 1.5 Platform facts found in the repo

* Android: the manifest keeps `INTERNET` (`scripts/build_android.sh`). There
  is no multicast-lock permission.
* Xbox UWP: `ports/uwp/Package.appxmanifest.in` declares `internetClient`,
  `internetClientServer` and `privateNetworkClientServer`. Whether the UWP
  LÖVE build includes lua-enet and luasocket is **unverified**.
  `Platform.canFetchRemote` notes that the UWP backend has no native HTTP
  bridge.
* Switch (love-nx): whether lua-enet and luasocket are present is
  **unverified**. `Platform.networkValidated` is false on NX and UWP.
* iOS: the overlay plist (`mobile/ios/overlays/love-ios.plist`) has **no
  `NSLocalNetworkUsageDescription`**, so LAN discovery and UPnP would be
  silently blocked on iOS 14 and later.
* macOS entitlements: JIT and library validation only. A non-sandboxed build
  needs no network entitlement.

### 1.6 Trivial fixes noted (not applied, because this phase is read-only)

* `LinkState.lua` header comment says "no relay server". It is out of date.
* `Gen3StartMenu.lua:293` drops LINK on FRLG. This looks like a side effect of
  the layout pass, not intent. The FRLG help-bar text needs a "link" entry
  when the row is restored.
* `tests/run_link_tests.lua` should document that `POKEPORT_DATA_DIR` is
  required.

---

## Part 2. Design

### 2.0 Principles

1. **The game is the server.** Every online feature has a host that is a
   player's running game: a link session, a world, or a world's GTS.
   Third-party infrastructure is optional and replaceable.
2. **One message layer, many transports.** LinkState, LinkBattle, Tournament
   and the new features talk to a `Channel` with the existing Net API. They
   never know whether bytes go over LAN, a UPnP-mapped port, a punched hole or
   a relay.
3. **Cartridge rules decide pairing.** Generation and family rules come from
   what the real games allowed. Port extensions (a Gen 1–3 GTS, worlds) are
   labelled as such.
4. **Only Pokémon and player data cross the wire.** No ROM bytes, maps,
   sprites, text or audio are ever sent. Each side renders the other's mon
   from its own ROM data.
5. **Backwards compatible.** v2 peers (0.7.x) still link with v3 peers for the
   Gen 1/2 flows. A v3 Gen 3+ peer refuses a v2 Gen 3+ trade, because v2 loses
   data.

### 2.1 Reachability: an honest layering

Not every pair of players can connect without third-party help. Carrier-grade
NAT (mobile data, many ISPs) and symmetric NAT cannot accept inbound traffic,
and two such players can only meet through a relay. The design tries the cheap
paths first and says plainly which path is in use.

Each candidate below is a way for the joiner to reach the host's ENet port
(UDP 7777 by default).

| Layer | How | Needs | Works when |
|---|---|---|---|
| **L0 LAN** | The host's LAN IPv4 goes in the code | nothing | same network (home, local play) |
| **L1 Port mapping** | The host asks the router to open UDP 7777. **NAT-PMP/PCP**: unicast UDP to gateway:5351. **UPnP-IGD**: SSDP M-SEARCH to 239.255.255.250:1900, then HTTP GET of the device description, then SOAP `AddPortMapping` and `GetExternalIPAddress`. All of this is plain luasocket (UDP, `socket.http`) and pure Lua XML scraping. | a router with UPnP or NAT-PMP enabled (common on home routers, often on by default) | the host is behind one consumer NAT that is not CGNAT. The external IP comes from the router, so no server is needed. |
| **L2 Manual forward** | The player forwards UDP 7777 themselves. The settings let them type their public IP or DNS name. | user effort | the same cases as L1 |
| **L3 Simultaneous open (hole punch) without a rendezvous** | **Both** players exchange codes. Each side binds 7777, learns its public IP (L1 `GetExternalIPAddress`, or optionally public STUN, see below), and both `enet:connect` to each other at the same time. ENet's connect packets act as punches. A tie-break on nonce order keeps one peer. | both public IPs known; NATs that preserve ports and map independently of the endpoint (most home NATs) | moderate. It fails on symmetric NAT and CGNAT. |
| **L4 Rendezvous-assisted punch** | Both sides connect over ENet to a **Link Hub** (2.9). The hub sees each side's observed `ip:port` (`tostring(peer)`) and tells each about the other. Both then connect directly from the **same ENet host socket**, so the NAT mapping the hub saw is the one used. | any reachable hub, self-hosted or community | most cone NATs, including when UPnP is off |
| **L5 Relay** | A hub forwards ENet packets between the pair, or the existing TCP `pokeserver` carries JSON lines. | a hub, or pokeserver | always, including CGNAT on both sides, at the cost of latency |

Swap rule: only the host needs to be reachable. If a direct join fails, the UI
offers "Let them host instead". The other player shows their code, which often
succeeds when one side is on mobile data.

STUN: Lua can bind a luasocket UDP socket on 7777, send one STUN Binding
Request to a public STUN server, read the mapped address, close the socket,
and then bind ENet on 7777. The NAT mapping usually survives the 30–120 s
until it is used. This uses a third party (for example
`stun.l.google.com:19302`), so it is **off by default** and offered as a
toggle ("Use a public address finder"). See the decisions in 2.13.

IPv6 is out of scope. lua-enet binds IPv4 only.

### 2.2 Invite codes

There are two kinds of code. Both use the existing Crockford-style alphabet
(`CodeEntry.CHARSET`, 31 symbols, no 0/O/1/I/L), shown in groups of four.

**Direct code** (serverless; L0–L3). It is a bit-packed value with a check
character:

```
ver:3  kind:2  flags:4 (hasPublic, hasLan, lanShort, customPort)
[public IPv4:32] [LAN: 16 low bits if lanShort (192.168/16, 172.16/12 low half), else 32]
[port:16 if customPort]  nonce:20  check:5 (CRC-5 over the rest)
```

With a public address, a 192.168 LAN address and the default port, the code
is 3+2+4+32+16+20+5 = 82 bits, which is **17 characters**, displayed as
`XXXX-XXXX-XXXX-XXXX-X`. A LAN-only code is 50 bits, or 10 characters.

`kind` is `0` for a link session, `1` for a world, and `2` for hub-assisted
(L4/L5). A hub-assisted code carries the hub's IPv4 and port plus a 20-bit
room ticket, so the joiner needs no prior configuration.

**Short room code** (6 characters, today's format): used only when the player
has a hub configured or chooses the pokeserver fallback. Both players must use
the same hub. It is offered as "Short code (uses <hub name>)".

The nonce is the session secret. The host rejects a `hello` whose `nonce` does
not match, so a port scanner cannot walk into a session. Codes expire when the
host closes the session.

Privacy: a direct code reveals the host's public IP to anyone it is shared
with. The SHOW CODE screen says this once, and hub codes avoid it.

Entry:

* A new `LongCodeEntry` widget scrubs with the d-pad as today and accepts
  `love.textinput` (keyboard and the mobile soft keyboard) and clipboard paste
  (`love.system.getClipboardText`).
* SHOW CODE also offers "Copy". Discord join secrets carry the full code.
* The check character catches typos before any packet is sent.

### 2.3 Session layer

`src/online/net/Transport.lua` wraps one ENet host:

* Multiple peers; 3 channels: 0 reliable session, 1 unreliable-sequenced world
  sync, 2 reliable bulk (GTS lists, party data).
* Peer limit: 1 for a link session, or the world cap.
* `Transport:channelFor(peerId)` returns an object with **exactly the Net
  API** (`send`, `poll`, `update`, `paired`, `closed`, `error`, `close`). This
  means `LinkState`, `LinkBattle`, `TradeSession` and `Tournament` work
  unchanged over any path. A world host relays a two-player session between
  two of its guests over this same channel abstraction, tagged
  `{sid=…}`.
* `Transport.loopbackHub(n)` returns n in-memory ends for tests, generalising
  `Net.loopbackPair`.

`src/online/net/Connector.lua` runs the reachability ladder. It takes a
decoded invite, tries the candidates in parallel with a deadline (LAN first,
then public, then punch, then relay), and reports which path won ("Connected
directly", "via router mapping", "via relay").

`Net.lua` stays, for v2 compatibility and for Tournament. The new modules sit
beside it.

### 2.4 Handshake v3 and versioning

`hello` gains these fields (all additive; a missing field means v2):

```
protocol = 3, gen = 1..5, game = "red"|"crystal"|"emerald"|"firered"|"platinum"|"heartgold"|"black"|…,
family = "rby"|"gsc"|"rse"|"frlg"|"dppt"|"hgss"|"bw",
wire = { mon = 3 },               -- MonCodec version
features = { "trade","battle","world","gts","chat" },
nonce = <from invite>, mapSet = <digest of map ids>  (worlds only)
battleFingerprint = <Fingerprint over battle surface only>
```

* `Handshake.checkCompat` keeps the engine-major check and the
  fingerprint-based verdicts, and adds `CompatRules.pair(localHello,
  remoteHello)`, which returns the allowed modes and the conversion to apply
  (2.5).
* `features` is intersected, so a client that lacks `world` still trades.
* `Version.linkProtocol` becomes 3.
* A v2 peer on Gen 1/2 still gets the v2 path verbatim. A v2 peer paired with
  a Gen 3+ v3 peer is refused with "Update the other game to trade". This is
  the only behaviour change for old peers, and it prevents silent data loss.

### 2.5 Mon wire format (MonCodec v3) and cross-generation rules

`src/online/MonCodec.lua` packs a **per-generation allowlist** and rebuilds
through the engine's own constructors (`Pokemon.applySeed`, `Stats.calc` with
ivs, evs and nature), so a tampered packet still cannot invent stats.

| Gen | Fields added over today's set |
|---|---|
| 1 | (unchanged) |
| 2 | happiness, pokerus, caughtData (time, level, location), shiny comes from DVs as today |
| 3 | personality, ivs (0–31), evs (≤255 each, ≤510 total), nature, abilitySlot, happiness, ball, metLevel, metLocation, metGame, otGender, language, pokerus, markings, contest stats, ribbons, isEgg and egg steps |
| 4 | gen 3 fields plus form, eggMet, shinyLeaves (HGSS), walker flags already in `extra`, fateful encounter |
| 5 | gen 4 fields plus hidden-ability flag (`natureIsOwnField`), the nature as its own field, dreamWorld flag |

`MonCodec.validate(data, packed)` checks and clamps: species exists, every
move exists, level 1–100, exp lies inside the level's range, IV, EV and PP-Up
bounds, nickname at most 10 or 12 characters, item exists in this game. It
also checks egg sanity: an egg has no nickname or moves beyond its learnset.
Validation failures name the mon, which is the strict-mode behaviour today.

**Pairing rules (`src/online/CompatRules.lua`), matching the cartridges:**

| Pair | Trade | Battle | Conversion |
|---|---|---|---|
| same game | Y | Y (lockstep if `battleFingerprint` matches) | none |
| R/B ↔ Y | Y | Y | none (Yellow's Pikachu happiness lives in `extra`) |
| G/S ↔ C | Y | Y | none |
| **Gen 1 ↔ Gen 2 (Time Capsule)** | Y | **N** | Gen 2→1: only species ≤151 and moves ≤165, no held item (refuse if holding one, as the cartridge does), no egg. Gen 1→2: the held item is derived from catchRate as the GSC Time Capsule does. Both sides set `timeCapsule = true`, so item-gated trade evolutions cannot fire. |
| R/S ↔ E ↔ FR/LG | Y | Y (host-authoritative if the battle surfaces differ) | FRLG cannot receive non-Kanto species until it has the National Dex (`CompatRules` reads the save flag); the receiving side greys those mons out. Emerald-only items are refused. |
| D/P ↔ Pt ↔ HG/SS | Y | Y | form gates: Giratina-O is refused into DP without the Griseous Orb (cartridge rule); HGSS-only items are refused on Pt. |
| B ↔ W | Y | Y | none |
| any other cross-generation pair | N | N | Offline one-way only: Pal Park (3→4) and Poké Transfer (4→5) as today. Online one-way transfer is a decision for the user (2.13). |

**Battles between different games in one family** (Pt vs HGSS, E vs FRLG)
cannot lockstep when the two data sets differ. LinkBattle gets a
**host-authoritative mode**: the guest sends `action` and the host runs the
only simulation and sends `event` packets. The message types already exist in
`Protocol.lua`'s vocabulary, and `newSpectator` already rebuilds a match from
traffic. The guest renders from its own ROM's sprites and text; both games
have every species in the family. Lockstep stays the default when the
fingerprints match.

Battle formats per generation: singles everywhere first. Gen 3+ link doubles
(Colosseum "Double Battle") and Gen 4/5 multi come as a later stream, because
`BattleState` already runs Frontier doubles. Level rules: the existing
ANY/50/100 picker, where 50 and 100 mean "scale down only" as the cartridges'
Colosseum rules do. A cartridge-style item clause and species clause are
toggles.

Trade animation: the link trade plays the generation's own sequence:
`Gen2TradeAnim` (Gen 2), `TradeAnim` (Gen 1/3), `Gen4TradeSequence` (Gen 4),
`Gen5TradeSequence` (Gen 5). The Gen 4 and Gen 5 sequences are already used by
in-game NPC trades.

### 2.6 LINK in every START menu

* Gen 1/2 `StartMenu.lua`: already present.
* Gen 3 `Gen3StartMenu.lua`: restore the row on FRLG, with a help-bar line.
* Gen 4 `Gen4StartMenu.lua`: a `Gen4StartMenu.linkRow(game)` beside
  `modsRow`. It appears when the party is non-empty and not during
  Safari, Bug Contest or Pal Park. It is inserted before EXIT and drawn as a
  word, like MODS.
* `HgssStartMenu.lua`: takes the next free button slot. If the 8 slots are
  full, LINK and MODS share one "PORT" button that opens a two-row submenu.
* `Gen5StartMenu.lua`: a half-height tab beside MODS.
* The LINK screen itself gets a DS-size (256×192) layout on dual-screen games
  (`GameVersion.isDualScreen`).

The new LINK menu:

```
LINK
  TRADE / BATTLE
     HOST  -> shows code (direct; "short code" if a hub is set) -> waits
     JOIN  -> enter code
  WORLDS
     HOST A WORLD / JOIN A WORLD / RECENT WORLDS
  GTS          (in a world, or on a hub; Gen 4/5 also via the Global Terminal)
  TOURNAMENT   (hub or relay)
  SETTINGS     (port, UPnP on/off, public address finder, hub address, privacy)
```

LAN discovery is a convenience: the host broadcasts a UDP beacon on 7778 and
JOIN lists nearby hosts. On iOS this needs the local-network permission.

### 2.7 In-game link rooms

Each room's script hook calls one entry point,
`require("src.online.LinkRooms").open(game, room, opts, onDone)`. It returns
the cartridge's own "connected" or "failed" answer into the script's result
variable, so every script keeps its own branches and text.

| Room | Hook | Behaviour |
|---|---|---|
| Gen 1 Cable Club | `cableClubReceptionist` (exists) | unchanged, now through the new menu |
| Gen 2 PC 2F (Trade Center, Colosseum, Time Capsule) | `Gen2Specials` rows that are `g2_unavailable` today: `CheckLinkTimeout_Receptionist`, `CheckBothSelectedSameRoom`, `CableClubCheckWhichChris`, `Special_Colosseum` | the receptionist saves, then opens LinkRooms with `room = trade/colosseum/timecapsule`. Success writes 1 and the script walks the player into the room; the session then starts when both are seated. "Please come again" stays the fail arm. |
| Gen 3 Cable Club / Colosseum (RSE, FRLG) | specials 28/29 `TryBattleLinkup`/`TryTradeLinkup`, 32/33/34 seats, 248 `ReducePlayerPartyToThree` | as Gen 2. Specials 415 and 416/417 (wireless) stay "no adapter" until the Union Room stream. |
| Gen 3 Union Room / Record Corner | specials 416, 417, 96 | later stream: Union Room maps to a world (2.8) scoped to that room |
| Gen 4 PC 2F: Colosseum and Union Room (Pt, HGSS), Wi-Fi Club | the colosseum receptionist commands; `checkhaswifilistvalidlogin` and `getwiflistvalidfriendscount` (`Gen4ScriptVM.lua:1649-1650`); `30e` greeting editor | the "Wi-Fi login" checks answer TRUE when an online identity exists (2.10). The Wi-Fi Club opens the code menu. The Union Room becomes a world instance on that map. |
| Gen 4 Global Terminal GTS | `trystartgtsapp` (`PtMiscCommands.lua:428`) | opens the GTS client (2.7a) |
| Gen 4 Wi-Fi Plaza | `2f7`, `checknowifiplazacooldown` | out of scope (minigames); keeps the no-login answer |
| Gen 5 PC link counter, Union Room, Driftveil GTS, Battle Subway Wi-Fi/Multi | `Gen5MiscFieldOps` 0x139 wireless, `Gen5BattleSubway` COMM_MULTI | trade and battle counters open LinkRooms. The Subway multi with a friend is a later stream. |

#### 2.7a GTS without a central server

Three options were weighed:

1. **Code-shared deposits.** Rejected. A serialized mon is about 100–200
   bytes, which would make the code too long, and there is no escrow, so the
   same mon can be "deposited" into many codes (cloning).
2. **A GTS in each player-hosted world.** Chosen as the baseline. The world
   host is the escrow: a deposit removes the mon from the depositor's save
   **and** the save is written before the host acknowledges. Matching and
   claiming run on the host. The host persists the GTS database on disk.
   Offline depositors claim their result the next time they join that world.
3. **The same GTS service inside the self-hostable Link Hub** (2.9). Chosen as
   the community option: an always-on GTS for a Discord group, a school, and
   so on, with no developer-run server.

Both hosts run **the same pure module**, `src/online/gts/GtsService.lua`, over
a storage adapter (LÖVE filesystem in a world host, plain files in the hub).

Pools follow the cartridges: one pool shared by D/P/Pt/HGSS, one for B/W.
For Gen 1–3 there are port-extension pools: RBY, GSC, and RSE+FRLG. Gen 1↔2
are not pooled together. Search covers species, level range and gender,
matching the cartridge GTS search. Cross-game deposits inside a pool pass
through `CompatRules` (an FRLG save without the National Dex cannot claim a
Hoenn mon).

The Gen 4/5 Global Terminal opens the GTS on the world the player is
connected to, or on their configured hub. With neither, it says the
cartridge's own "could not connect" line.

### 2.8 Worlds ("MMO style"), host-authoritative

What a world is: the host's running game is the authority for **presence,
social state, sessions between players, and the world GTS**. **Each player
still plays their own save** in their own game; a world is a shared overlay,
like the Union Room or Wi-Fi Plaza, not a shared single save. This keeps the
single-player engine unchanged and makes progression cheating irrelevant to
other players.

* **Membership.** All members must share the same `mapSet` digest. A digest
  of the map-id list means R/B/Y can share, G/S can share, FR/LG can share,
  and Pt and HGSS cannot (different regions). Crystal and Emerald differ
  slightly from their pairs, so pairs only join when the map ids match.
* **Topology.** A star. Every client connects to the host only. The host
  forwards to the others. ENet channel 1 (unreliable-sequenced) carries
  movement, and channel 0 carries everything else.
* **Player cap.** Default 8, configurable up to 16. The bandwidth is trivial:
  about 60 B × 10 Hz × 16 ≈ 10 KB/s outbound on the host. The real limits are
  host upload on mobile and on-screen clutter.
* **What syncs:**

  | Data | Rate and channel |
  |---|---|
  | `pos`: map id, cell x/y, facing, step phase, movement mode (walk, run, bike, surf), visibility | 10 Hz while moving or on change, channel 1; the host forwards only to players on the same map or a connected map |
  | `look`: avatar (the player sprite id the save already uses, through `Runtime.call("player.sprite")`), follower species (Yellow's Pikachu, HGSS walking mon), name, trainer id (public 16 bits), title | reliable, on join and on change |
  | `emote`: the cartridge's emote bubbles (!, ?, ♪, heart), with a short cooldown | reliable |
  | `chat`: 60 characters, profanity filter optional (port `other/profanity.lua` rules), rate-limited by the host | reliable |
  | `invite`: trade or battle request to a player id, then accept, then the host opens a relayed two-player session (`sid`) and both clients push the normal LinkState trade or battle over `Transport:channelFor` | reliable |

* **Rendering remote players.** Each remote player becomes a **ghost NPC**: an
  entry in `OverworldState.npcs` flagged `remote = true, noCollide = true,
  noInteract = false`, using the sprite and walking code all renderers
  already draw. That covers GB/GBA 2D and Gen 4/5 `Gen4Ground` billboards.
  Talking to a ghost opens "TRADE / BATTLE / CHAT / CANCEL". One small,
  anchored hook in `OverworldController` is needed: skip `remote` NPCs in
  collision, scripted movement and save-time persistence.
* **Persistence on the host.** `save/online/worlds/<worldId>/`, with
  `world.json` (name, cap, rules, created), `members.json` (identity token
  hash → name, last seen, bans), `gts.json`, and `mail.json` (offline trade
  results). Atomic write-rename. The world id is random. Re-hosting the same
  world gives a new code but the same identity.
* **Identity.** On first use each install creates a random 128-bit token
  (`save/online/identity.json`). The host stores only `love.data.hash("sha256",
  token)`. This is not an account system. It lets a host recognise a returning
  player and route GTS results.
* **Anti-cheat basics.**
  * The host validates every party and deposit it receives with
    `MonCodec.validate`, and with `Fingerprint` records for the pool's
    reference data.
  * The host refuses joins whose handshake verdict is `refused`. For a public
    world (shared outside friends) it requires `Handshake.onlineAllowed`
    (vanilla).
  * Lockstep battles are protected by the per-turn state hash, as today.
    Host-authoritative battles trust the host, which is acceptable in the
    host's own world and is documented.
  * Rate limits on chat, emotes and invites.
  * Hosts can kick or ban by identity hash.
  * Honest limit: a modified client can always lie about its own save. The
    goal is that it cannot corrupt anyone else's.
* **Union Room mapping.** In Gen 3–5 Union Room maps, the world overlay is
  scoped to that map, and the cartridge's Union Room seating, greetings and
  avatars come from the game's own scripts where ported. This is a later
  stream.

### 2.9 The Link Hub (optional, self-hostable)

`tools/online-hub/` is a **headless LÖVE program** (`conf.lua` disables
window, graphics and audio) that reuses `src/online/*`. It also runs under any
LuaJIT that has lua-enet and luasocket. It is a single process that a player
or community runs on a PC, a Raspberry Pi or a VPS:

* **Rendezvous** (L4): room tickets, then each side's observed endpoints are
  exchanged.
* **Relay** (L5): ENet packet forwarding for pairs that could not punch, with
  a bandwidth cap per pair.
* **Short codes**: 6-character room codes, like pokeserver.
* **Optional services**: GTS (`GtsService`), a persistent always-on world
  (`WorldHost` with no local player), and tournaments.

The JSON-lines TCP protocol of `pokeserver` is also served on a second port,
so 0.7.x clients pointed at a hub with `POKEPORT_RELAY_ADDR` keep working.

Lua is chosen over Python so the hub runs the **same** GTS, world and
validation code as the game. Validation needs the game data, which the hub
gets the same way the game does: the hub operator points it at their own
`data/generated` cache. Without data the hub refuses GTS. No ROM data ships
with the hub.

The hub's modules now live in `src/online/hub/` and ship with the game; the
launcher runs the same hub in a background thread (sidebar "Online Hub",
docs/launcher.md). `tools/online-hub/` remains the headless entry point.

### 2.10 Platform support

| Platform | Host | Join | Port mapping | Notes |
|---|---|---|---|---|
| Windows / Linux / macOS | Y | Y | UPnP + NAT-PMP | First host triggers the OS firewall prompt (Windows Defender, macOS "accept incoming connections"). |
| Android | Y on Wi-Fi; on mobile data usually not reachable (CGNAT), so offer swap or hub | Y | NAT-PMP; UPnP (SSDP replies are unicast, so no multicast lock is needed for M-SEARCH, but add `CHANGE_WIFI_MULTICAST_STATE` for the LAN beacon) | The OS kills sockets in background; sessions end on suspend, as a cable pull. |
| iOS (sideload) | Y on Wi-Fi | Y | NAT-PMP/PCP (unicast) only. SSDP multicast needs Apple's `com.apple.developer.networking.multicast` entitlement, so skip UPnP. | Add `NSLocalNetworkUsageDescription` to `mobile/ios/overlays/love-ios.plist`. Sockets die in background. |
| Xbox (UWP, Dev Mode) | likely Y (`internetClientServer` and `privateNetworkClientServer` declared) | Y | UPnP plausible | Unverified: enet and luasocket in the UWP LÖVE build. UWP blocks loopback between apps, so test with two devices. Gate at runtime with `Net.available()` and a new `Platform.canHostOnline()`. |
| Switch (love-nx homebrew) | unverified | unverified | — | Gate at runtime. Warn once that going online with homebrew can get a console banned by Nintendo; this is the user's risk. |
| Web build | N | N | — | No UDP. Hub-relay over WebSocket would be a separate project. |

### 2.11 Security and privacy

* Allowed on the wire: hello and handshake fields, the party and mon records
  (MonCodec), the trainer name, the public trainer id, the avatar id, map
  ids and cells, chat, emotes, GTS listings, and battle actions and events.
  **Never sent:** ROM bytes, generated caches, maps, graphics, text, audio,
  file paths, the full save, or the identity token itself (only its hash, to
  the host).
* Every inbound message is size-capped (64 KB reliable, 512 B unreliable),
  JSON depth-capped (`Protocol.plainCopy` already caps depth at 8), and
  type-checked. Unknown types are dropped.
* ENet is unencrypted. Nothing secret travels, apart from the session nonce,
  which only gates entry. Say so in the docs.
* Showing a direct code reveals the host's IP. Hub codes do not.
* Mods: `Handshake.onlineBlockers` stays the gate for public worlds and hubs.
  Private sessions keep today's negotiated `subset` and `full` behaviour.
* The `pokemon.received` event fires as today, so mods validate their own
  `extra` namespaces.

### 2.12 Interfaces (stable contracts between streams)

```lua
-- src/online/net/Transport.lua
Transport.new{ port=, maxPeers=, channels=3 } -> t
t:listen() / t:connect(endpoints, nonce) ; t:update() ; t:events() -> {connect|receive|disconnect}
t:channelFor(peerId) -> netLike        -- exactly the Net API used by LinkState/LinkBattle
Transport.loopbackHub(n) -> {t1..tn}   -- tests

-- src/online/net/PortMap.lua
PortMap.discover(timeout) -> gw | nil, why ; PortMap.map(gw, port, "UDP", lease) -> externalIp, extPort | nil, why
PortMap.unmap(gw, port)  -- parse functions are pure and fixture-tested

-- src/online/InviteCode.lua
InviteCode.encode{ kind=, public=, lan=, port=, nonce=, hub= } -> "XXXX-XXXX-..." ; InviteCode.decode(text, myLanIp) -> invite | nil, why

-- src/online/net/Connector.lua
Connector.join(invite, opts) -> job ; job:update() ; job.state "trying"|"connected"|"failed" ; job.path ; job.transport

-- src/online/MonCodec.lua / CompatRules.lua / HandshakeV3 (extends Handshake.hello)
MonCodec.pack(data, mon, gen) -> packed ; MonCodec.unpack(data, packed, opts) -> mon | nil, why ; MonCodec.validate(...)
CompatRules.pair(localHello, remoteHello) -> { trade=bool, battle="lockstep"|"host"|false, convert=fn|nil, reasons }

-- src/online/gts/GtsService.lua (pure) ; GtsClient.open(game, { channel=netLike, pool= }) (UI)
-- src/online/world/WorldHost.lua / WorldClient.lua / Presence.lua ; message schemas in WorldProtocol.lua
-- src/online/LinkRooms.lua: LinkRooms.open(game, room, opts, onDone(resultCode))
```

### 2.13 Decisions that belong to the user

| # | Decision | Recommendation |
|---|---|---|
| 1 | Keep the existing relay `147.182.215.255:7778` as the default fallback? | **Keep it as an opt-out fallback for short codes and tournaments only.** Direct codes are always tried first. Let SETTINGS replace it with any Link Hub. It is a hard-coded raw IP with no TLS and a single point of failure, so the hub's pokeserver-compatible port gives a migration path. |
| 2 | Run a public default Link Hub (developer-hosted) for rendezvous and relay? | Optional. It makes CGNAT and mobile pairs work out of the box. If the user prefers "no server at all", ship with **no** default hub, and those pairs must use swap, a self-hosted hub, or pokeserver. |
| 3 | Use public STUN (Google) for address discovery? | Off by default, as a toggle. |
| 4 | World player cap | Default 8, max 16. |
| 5 | Gen 1–3 GTS (not a cartridge feature) | Yes, as per-family pools labelled a port extension. |
| 6 | Online one-way cross-generation transfer (Pal Park or Poké Transfer between two players) | No. The cartridges were same-owner, and the offline features already exist. |
| 7 | Mods in worlds | Vanilla for public worlds and hubs; host's choice (fingerprint-matched) for private ones. |
| 8 | The `gen2online` mod and its HTTP server | Leave it as a separate legacy mod. Mine its quest and chat ideas later; do not build on its central-server architecture. |
| 9 | Hub language | Lua (headless LÖVE), to reuse the validation, GTS and world code. Python would duplicate it. |
| 10 | Union Room and Wi-Fi Plaza fidelity | Union Room as a scoped world: yes, in a later stream. Wi-Fi Plaza minigames: out of scope. |

### Decisions

Made by the user on 2026-11-03. Where they differ from the recommendations in
2.13, these win.

| # | Decision |
|---|---|
| 1 | The relay is used **only** for 6-character short codes and for tournaments. Direct codes never touch it. |
| 4 | The world player cap is 8 by default, 16 at most. |
| 5 | Gen 1–3 get GTS pools as a port extension (RBY, GSC, RSE+FRLG), labelled as such. |
| 6 | Cross-generation online: **yes, one way upward.** Two players can move a mon from the older game to the newer one, as a one-way gift (never a swap), under the cartridge transfer rules the port already has offline. Gen 3 → Gen 4 follows Pal Park (`src/world/Gen4PalPark.lua`: no Egg, none of the eight Game Pak HM moves, National Dex needed in the DS game). Gen 4 → Gen 5 follows Poké Transfer (`src/world/Gen5PokeTransfer.lua`: no Egg, no held item, none of Gen IV's HM moves). Gen 1/2 onward (a Gen 7-style Transporter) and two-step jumps (Gen 3 → Gen 5) are out of scope. Handshake verdict `transfer`; implemented in `src/online/Transfer.lua` (`TransferSession`) and `CompatRules.TRANSFER` (WS3). |

---

## Part 3. Implementation plan

The streams are split so that **no two streams edit the same file**. New
modules live under `src/online/`, which no current stream owns. Shared
existing files are assigned to exactly one stream. The other parallel sessions
in this repo edit the same tree, so every edit to an existing file must be an
anchored edit, not a rewrite.

### WS1: Transport, port mapping, connector

* **New:** `src/online/net/Transport.lua`, `src/online/net/PortMap.lua` (SSDP,
  UPnP SOAP, NAT-PMP, PCP), `src/online/net/Connector.lua`,
  `src/online/net/Punch.lua`, `src/online/net/Stun.lua` (toggle),
  `src/online/net/LanBeacon.lua`.
* **Tests:** `tests/online_transport_test.lua` (loopbackHub: n-peer delivery,
  channels, channelFor and the Net-API conformance suite run against
  `Net.loopbackPair` and channelFor alike); `tests/online_portmap_test.lua`
  (pure parsers on captured SSDP, device XML, SOAP and NAT-PMP fixtures; no
  network); `tools/online/twoproc/` (two LÖVE processes on 127.0.0.1: host
  and join, connect, exchange 1,000 messages, close. Each process uses a
  `love.errorhandler` that prints and calls `os.exit(1)`).
* **Acceptance:**
  * channelFor passes the Net conformance suite.
  * Two processes pair on localhost and over LAN.
  * PortMap round-trips mapping and unmapping against a real router in manual
    QA, and against fixtures in CI.
  * The Connector picks LAN over public when both work.

### WS2: Invite codes and entry UI

* **New:** `src/online/InviteCode.lua`, `src/ui/online/LongCodeEntry.lua`,
  `src/ui/online/ShowCode.lua` (copy, privacy note).
* **Tests:** `tests/online_invite_test.lua` (encode and decode round trip for
  every flag combination, a check character that rejects every single-symbol
  typo, LAN-prefix rebuild).
* **Acceptance:** a direct code is at most 17 characters with a public
  address, and at most 10 LAN-only. Paste and textinput work on desktop and
  Android.

### WS3: MonCodec, CompatRules, Handshake v3

* **New:** `src/online/MonCodec.lua`, `src/online/CompatRules.lua`,
  `src/online/TimeCapsule.lua`.
* **Owns edits to:** `src/link/Protocol.lua` (dispatch `packMon`/`unpackMon`
  to MonCodec when `wire.mon >= 3`), `src/link/Handshake.lua` (v3 fields,
  `CompatRules`), `src/link/Fingerprint.lua` (`battleFingerprint`),
  `src/core/Version.lua` (`linkProtocol = 3`).
* **Tests:** `tests/online_moncodec_test.lua`, run once per cache with
  `POKEPORT_DATA_DIR` over all 13 caches under `G:/Gen2Recomped/*`. For every
  species, a random mon must round-trip **with identical stats, nature,
  ability, shininess and gender**; a fuzz pass must show that validate rejects
  out-of-range data. `tests/online_compat_test.lua`: the pairing matrix in
  2.5, Time Capsule conversions, the FRLG National Dex gate.
  `tests/run_link_tests.lua` must still pass, because the v2 path is
  unchanged.
* **Acceptance:** the round-trip probe in 1.4 reports no lost fields on
  Emerald, FireRed, Platinum, HeartGold and Black.

### WS4: LINK menu and START-menu entries

* **Owns edits to:** `src/link/LinkState.lua` (new menu tree, DS layout,
  per-generation trade animation selection, Connector and InviteCode wiring),
  `src/ui/StartMenu.lua`, `src/ui/Gen3StartMenu.lua` (FRLG row and help
  text), `src/ui/Gen4StartMenu.lua` (`linkRow`), `src/ui/HgssStartMenu.lua`,
  `src/ui/Gen5StartMenu.lua`.
* **Depends on:** WS1, WS2 and WS3 interfaces only. Stub them with
  loopbackHub until they land.
* **Tests:** a menu-row test per game family (the row is present with a party
  and hidden during Safari, Bug Contest or Pal Park); a LÖVE harness shot of
  the LINK screen on Red, Emerald, FireRed, Platinum, HGSS and Black; a
  loopback trade per generation that ends in the right trade sequence.
* **Acceptance:** LINK is visible and opens on all 7 families, and trade
  works end to end over loopback on each.

### WS5: Link battle (cross-game and Gen 3+ rules)

* **Owns edits to:** `src/link/LinkBattle.lua` (host-authoritative mode,
  generation-correct level rules).
* **New:** `src/online/BattleRules.lua`.
* **Tests:** extend the scratch `battle_probe.lua` into
  `tests/online_battle_gen_test.lua`. Its driver chooses a move with PP left,
  and every cache's battle must finish with mirrored HP. Host-authoritative
  Pt↔HGSS and E↔FR battles must finish, with the guest's view matching the
  host's events. The `link_desync_fuzz.lua` pattern applies per generation.
* **Acceptance:** a full battle finishes on every family with no desync;
  cross-game in-family battles finish in host mode.

### WS6a: In-game link rooms, Gen 1–3

* **New:** `src/online/LinkRooms.lua`.
* **Owns edits to:** `src/script/Gen2Specials.lua` and the `g2_unavailable`
  rows in `src/script/Gen2ScriptVM.lua`; the link block of
  `src/script/Gen3Commands.lua` (anchored at "THE LINK, ANSWERED…");
  `src/script/Gen3SpecialsFRLG.lua` (the link block at line 543).
* **Tests:** headless script runs of each receptionist with a fake LinkRooms
  that answers success or fail, and checks the script reaches the right
  branch.

### WS6b: In-game link rooms and Global Terminal, Gen 4–5

* **Owns edits to:** `src/script/PtMiscCommands.lua` (Wi-Fi gates and
  `trystartgtsapp`), the Wi-Fi rows of `src/script/Gen4ScriptVM.lua`
  (1648-1653), `src/script/Gen5MiscFieldOps.lua` (0x139), and the link counter
  rows of `src/script/Gen5BattleSubway.lua`.
* **Calls:** `LinkRooms.open` (WS6a) and `GtsClient.open` (WS7).
* **Tests:** as WS6a, plus "no identity" keeps today's no-login branches.

### WS7: GTS service and UI

* **New:** `src/online/gts/GtsService.lua` (pure: deposit, escrow, search,
  offer, match, claim, expiry), `src/online/gts/GtsStore.lua` (adapters),
  `src/online/gts/GtsClient.lua`, `src/ui/online/GtsScreen.lua` (a generic UI
  in the cartridge's window style; 256×192 on DS).
* **Tests:** `tests/online_gts_test.lua`. Pure service tests: no duplication
  under concurrent claim, escrow survives a host restart (store reload),
  cross-pool rejection, the FRLG gate. Also a loopbackHub client-and-host flow.
* **Acceptance:** deposit, offer, claim and withdraw over loopback; a host
  restart preserves state; no path ends with the mon in two places.

### WS8: Worlds (presence, chat, invites, persistence)

* **New:** `src/online/world/WorldHost.lua`, `WorldClient.lua`,
  `WorldProtocol.lua`, `Presence.lua` (ghost NPCs), `Chat.lua`,
  `WorldStore.lua`, `Identity.lua`, and `src/ui/online/WorldMenu.lua`,
  `ChatOverlay.lua`, `GhostInteract.lua`.
* **Owns one anchored edit to:** `src/world/OverworldController.lua`: skip
  `npc.remote` in collision, scripted movement, persistence and
  `trainerDefeated`. Everything else goes through the existing `map.entered`,
  `world.stepped` and `player.warped` events.
* **Tests:** `tests/online_world_test.lua` (loopbackHub with 1 host and 3
  clients: join, leave, interest filtering per map, chat rate limit, invite →
  relayed trade over channelFor, ban); a two-process LÖVE harness where the
  client walks 10 steps and the host sees the ghost at the right cell. Run
  only one LÖVE harness at a time.
* **Acceptance:** 8 clients on loopback hold steady CPU; ghosts render on GB,
  GBA and DS renderers; a trade between two guests completes through the host.

### WS9: Link Hub

* **New:** `tools/online-hub/{conf.lua, main.lua, README}` (rendezvous, relay,
  short codes, a pokeserver-compatible TCP port, optional GtsService and
  WorldHost).
* **Tests:** `tools/online-hub/selftest.lua` (in-process rendezvous of two
  Transport ends and relay forwarding); a two-process run with the hub plus
  two clients on 127.0.0.1. `tests/drivers/net_relay_smoke.lua` must pass
  against the hub instead of pokeserver, and **must not contact the real
  relay**.
* **Acceptance:** an L4 punch succeeds on localhost (simulated); a 0.7.x
  client pointed at the hub with `POKEPORT_RELAY_ADDR` pairs.

### WS10: Platform and settings

* **Owns edits to:** `src/core/Platform.lua` (`canHostOnline`,
  `canPortMap`), `mobile/ios/overlays/love-ios.plist`
  (`NSLocalNetworkUsageDescription`), `scripts/build_android.sh` (multicast
  permission), and the online SETTINGS screen
  (`src/ui/online/OnlineSettings.lua`: port, UPnP, STUN, hub, privacy).
* **Tests:** Platform unit tests per OS string; manual QA on each device.

### Order and dependencies

```
WS1 ─┬─> WS4 ──> (release: trade/battle by code, all games)
WS2 ─┤
WS3 ─┴─> WS5
WS7 ──> WS6b
WS6a ─> WS6b (LinkRooms API)
WS1 + WS3 ─> WS8 ─> WS9 (hub reuses WorldHost/GtsService)
WS10 any time
```

WS1, WS2, WS3, WS7 and WS10 can start immediately in parallel. The first
user-visible milestone is WS1–WS4, which gives LINK in every game, trading and
battling by code, and correct Gen 3–5 data.

### Test conventions

* Headless: `POKEPORT_DATA_DIR=G:/Gen2Recomped/<game>/data/generated python
  tools/run_lua_check.py tests/<x>.lua`.
* LÖVE harnesses: one at a time; `love.errorhandler` prints and calls
  `os.exit(1)`; output goes to `G:/Gen2Recomped/scratch_claude/online/`. Never
  run `lovec .` in the repo root.
* No test contacts any external host. Network tests bind 127.0.0.1 only.

---

## Part 4. As built

Where the build differs from Parts 1 to 3, and what each stream ended up as.

### Modules

| Area | Where |
|---|---|
| Transport, ladder, router mapping | `src/online/net/` (Transport, Connector, PortMap, Punch, Stun, Relay, LanBeacon, ConnTest) |
| Invite codes and their screens | `src/online/InviteCode.lua`, `src/ui/online/{LongCodeEntry,ShowCode,CodeStyle}.lua`, `src/online/QrCode.lua` |
| Mon wire, compatibility, cross-game | `src/online/{MonCodec,CompatRules,TimeCapsule,Transfer}.lua`, `src/link/Handshake.lua` |
| LINK menu | `src/link/LinkState.lua`, START menus |
| Battles | `src/online/{LinkBattleModern,BattleRules}.lua`; four players: `src/online/{MultiBattle,MultiNet,MultiLobby}.lua`; the BW friend train: `src/online/SubwayMulti.lua` |
| Link rooms | `src/online/{LinkRooms,LinkRoomPeer,Plaza}.lua`, `src/script/{Gen2,Gen3,Gen45}LinkRooms.lua` |
| GTS | `src/online/gts/`, `src/online/HubGts.lua`, `src/ui/online/GtsScreen.lua` |
| Worlds | `src/online/world/`, `src/ui/online/{WorldMenu,ChatOverlay,GhostInteract,WorldUi}.lua` |
| Link Hub | `src/online/hub/` (moved from `tools/online-hub`, which keeps the headless entry), `src/online/LauncherHub.lua`, `src/ui/online/LauncherHubScreen.lua` |
| Settings, platform | `src/ui/online/{OnlineSettings,OnlineGate}.lua`, `Platform.online()` |

### Invite codes (2.2)

The format is a mixed-radix number, not bit fields: the header is
version(8) x kind(3) x hasPublic(2) x lanMode(4: none, short, ten, full) x
customPort(2), and the check symbol is a weighted sum mod 31, which catches every
single typo and every swap of neighbours (a CRC over the bits can't promise that).
Public + 192.168 = 17 symbols; LAN only = 10.

**Format version 2** adds one field, `pubPort`, on a code with a public address,
for a router that maps a different outside port. It is written only when the code
carries a LAN address too and the ports differ (`publicPort`); every other code
stays version 1, so older builds read them. An older build shown version 2 says
"update to join". This replaces the warning `encode` used to return.

**Hub codes carry both addresses** when both are known: the hub's public address
in the public slot, its LAN address in the LAN slot, and the outside port as above.
`Connector` tries the LAN address first (2.5 s), so friends on the same Wi-Fi don't
depend on router hairpin. A launcher hub share code is ticket 0 ("a hub door"): a
game's JOIN takes it too, pings the hub, keeps it, and offers its world or HOST.

### Connection test (new)

OPTIONS → ONLINE → CONNECTION TEST (`src/online/net/ConnTest.lua`): LAN address,
whether the port is free here, and a short (300 s) router mapping that is closed
again, which gives the method, the outside port and the public address the ROUTER
reports. Verdicts: `internet`, `manual`, `blocked` (the router's own address is
carrier NAT or private), `lan`, `offline`. It contacts the router only, and says
that only a friend's game can prove the last step. Tested against a fake IGD; **never
on a real router**.

### Link rooms (2.7)

The cartridge's walk is kept: a receptionist links ("connect"), the script walks the
player in, and the seat or spot resumes the session.

* **The other player's avatar.** While a session is held both games exchange
  `lr_pos` over the session's channel (`LinkRoomPeer`), shown with the ghost NPC from
  worlds (`Presence.makeRoomGhost`): Gen 3, Platinum, HGSS. Gen 2's rooms keep the
  script's own seated friend sprite (`CableClubCheckWhichChris`).
* **More than one round per visit.** A room session stays up after a battle or a trade
  (`LinkState` `onRoundEnd`, `LinkRooms._rearm`, battles run `keepNetOpen`). `lr_ready {
  round }` gates the next round until both games are back from their closing screens,
  so a battle's loop can't swallow the next hello. Step off the spot and back on (or
  use Gen 2's console again). Leaving the room's map ends the link for both
  (`lr_leave`). A LINK-menu peer, or a build without `lr_room` v2, gets one round as before.
* **Gen 3 door.** The rooms' door warps name the dynamic warp; `SetCableClubWarp` now sets
  it to the 2F door (the warp event nearest the walk's end), so walking out lands on the
  door and the 2F's frame script walks them down. The Direct Corner's walk to the door now
  plays: the first `waitstate` after specials 416/417 used to take the warp at once.
* The Union Room lists only world members who are in a Union Room themselves
  (scoped by `Presence.presenceRoom` = "@union"); it is a list on a screen, not the
  cartridge's walkable room with its seating and greetings. Its MULTI rows are also in
  the world menu.

### BW Wireless Multi Train

`SubwayMulti` keeps its own `sw_*` messages in place of script functions 0x190-0x1A0,
and does not run the car scripts' comm branches: both players stand on the car (Z075,
friend beside you) from the first battle to the last, with no walk-in and no trainers
walking up. REST works between cars (`save.gen5Subway.friendRest`, not the counter's
one-player "rested" bit), and the train carries on only when both saves hold the same
one. Super Multi (Z072, mode 8) runs the same path.

### Platform bridges (never compiled here)

`love.system.shareText` (Android: `GameActivity.shareText`, ACTION_SEND chooser; iOS:
`GRPickerBridge.shareText`, UIActivityViewController through `patch_love_src.py`) and
`love.system.acquireMulticastLock` / `releaseMulticastLock` (Android only;
`LanBeacon` holds it while a listener is open, and `Platform.online().canBroadcast` is
true when the bridge exists). **There is no Android or iOS toolchain here: these were
written from the existing pickFile / walkerNotify pattern and have not been built or
run.** Lua falls back to copy when `shareText` is missing. There is no camera access
in LÖVE: the app says so and asks for the phone's camera app and PASTE.

### Tournaments

The host's rules gain FORMAT (SINGLE / DOUBLE) on Gen 3 and up; double needs at least two
Pokémon a side. The hub echoes it in the roster, and each match's host deals it. The old
pokeserver does not echo it, so there only the creator's own matches are doubles.

### Not done

* Worlds have no hub or relay path of their own: direct codes, or a hub-hosted world.
* The walkable Union Room (seating, greetings), Wi-Fi Plaza minigames and 3D square, Record
  Mixing and Berry Crush over the link.
* The BW friend train's cartridge scripts, as above; BW's own trainer AI (`/a/1/7/1`).
* Router mapping on a real router; Android and iOS on real devices; Switch and Xbox.
