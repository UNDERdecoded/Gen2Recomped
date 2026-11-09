-- Handshake v2 (D8): the `hello` both peers exchange on pairing and the
-- compatibility verdict drawn from the two of them.
--
-- v1 builds sent `{type="hello", name, mode}` and nothing else.  Every field
-- here is additive, and a peer that omits `protocol` is by construction a
-- pre-mod build running unmodified content -- so a missing `protocol` reads
-- as "peer is vanilla" and the v1 code path is taken verbatim.  That keeps
-- old installs byte-compatible instead of locking them out.

local Fingerprint = require("src.link.Fingerprint")
local Schemas = require("src.mods.Schemas")
local Version = require("src.core.Version")

local Handshake = {}

Handshake.PROTOCOL = Version.linkProtocol or 2

-- writing into any of these changes what a lockstep turn or a rebuilt trade
-- mon looks like, which is what a v1 peer cannot know about us
local LINK_SURFACE = {
  pokemon = true, moves = true, type_chart = true, statuses = true,
  move_effects = true, balls = true, rulesets = true, constants = true,
  link_fields = true,
}

Handshake.LINK_SURFACE = LINK_SURFACE

local function loader(game)
  return game and game.mods or nil
end

-- every enabled mod, sorted so both peers see one order.  The whole set
-- rides the wire because the incompatibility screen diffs these arrays to
-- name what is missing; only the affects-link ones fold into the digest.
function Handshake.mods(game)
  local mods = {}
  local mod = loader(game)
  if not mod or not mod.status then return mods end
  local ok, status = pcall(mod.status, mod)
  if not ok or not status then return mods end
  for _, manifest in ipairs(status.loaded or {}) do
    mods[#mods + 1] = { id = manifest.id, version = manifest.version,
                        affectsLink = manifest.affects_link ~= false,
                        language = manifest.language == true }
  end
  table.sort(mods, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return mods
end

-- cheap answer to "can I link with a peer that assumes vanilla?": true as
-- soon as one enabled mod either declares affects_link or has written a
-- record into a link-surface registry
function Handshake.linkModified(game)
  local mod = loader(game)
  if not mod then return false end
  for _, entry in ipairs(Handshake.mods(game)) do
    if entry.affectsLink then return true end
  end
  for name, registry in pairs(mod.content or {}) do
    if LINK_SURFACE[name] then
      for _, list in pairs(registry.ops or {}) do
        for _, entry in ipairs(list) do
          if entry.owner and entry.owner ~= Schemas.ENGINE then return true end
        end
      end
    end
  end
  return false
end

-- #501: the registries a declared translation may write, and nothing else.
-- `text` is the ROM's dialogue, `strings` the engine's own authored text
-- (src/mods/Schemas.lua R.text / R.strings) and `font` the glyphs a
-- language with accents needs.  None of the three is hashed into the
-- fingerprint (src/link/Fingerprint.lua header), so two peers reading the
-- same game in different languages stay in lockstep -- which is also what
-- the cable did: TradeCenter_PrintPartyListNames (pokered
-- engine/link/cable_club.asm) names the peer's party out of the local
-- ROM's table, only the trainer name and the party bytes travel.
-- text_pointers is deliberately out: its rows carry mart inventories and
-- nurse/pc flags, which are gameplay, not language.
local LANGUAGE_REGISTRIES = { text = true, strings = true, font = true }

Handshake.LANGUAGE_REGISTRIES = LANGUAGE_REGISTRIES

-- The manifest's `language = true` is the author's claim; this is the
-- check.  A mod counts as a translation only if every op it appended
-- landed in a language registry, it subscribed no code (a hook or listener
-- runs inside the battle the two peers are lockstepping) and it asked for
-- no permission.  Online play meets strangers, so nothing here may rest on
-- the manifest alone.  A patched client can still lie about its own mods --
-- the fingerprint, not this, is what keeps the shared simulation honest;
-- this gate is what keeps an honest install from being told to turn its
-- language off.
local function translationOnly(mod, id)
  local record = mod.mods and mod.mods[id]
  local manifest = record and record.manifest
  if manifest and #(manifest.permissions or {}) > 0 then return false end
  for name, registry in pairs(mod.content or {}) do
    if not LANGUAGE_REGISTRIES[name] then
      for _, list in pairs(registry.ops or {}) do
        for _, entry in ipairs(list) do
          if entry.owner == id then return false end
        end
      end
    end
  end
  for _, chain in pairs((mod.hooks and mod.hooks.chains) or {}) do
    for _, entry in ipairs(chain) do
      if entry.owner == id then return false end
    end
  end
  for _, list in pairs((mod.events and mod.events.listeners) or {}) do
    for _, entry in ipairs(list) do
      if entry.owner == id then return false end
    end
  end
  return true
end

-- the enabled mods that keep this install out of online play, in the
-- id order Handshake.mods sorts: everything except verified translations.
-- LinkState:offerVanillaRestart names these and switches off exactly these.
function Handshake.onlineBlockers(game)
  local mod = loader(game)
  local blockers = {}
  for _, entry in ipairs(Handshake.mods(game)) do
    local allowed = entry.language and not entry.affectsLink
      and mod ~= nil and translationOnly(mod, entry.id)
    if not allowed then blockers[#blockers + 1] = entry end
  end
  return blockers
end

-- online play (the relay-based online match / tournament flows in
-- LinkState/Tournament) meets strangers, not a coordinating friend, so it
-- skips the LAN path's per-peer compatibility negotiation entirely and
-- just requires a vanilla simulation on both ends: no mod-added Pokemon, no
-- surprises.  #501 carves out translations, because a language is not a
-- simulation: a mod that only rewrites text is invisible to the wire and
-- may stay on, so an English player and a Spanish one can meet the way two
-- regional carts always could.  Mods only ever get baked in at boot
-- (Loader:load), so this is a gate on attempting to go online, not a live
-- mod toggle -- the player disables mods via the mod manager and relaunches.
function Handshake.onlineAllowed(game)
  return #Handshake.onlineBlockers(game) == 0
end

-- the link features this build offers; a hello's list is intersected with
-- the peer's (Handshake.features), so a client without `world` still trades
Handshake.FEATURES = { "trade", "battle" }

-- mode is nil on the guest: it pairs and announces itself before the host
-- has picked, and compatibility is decided from the two hellos, not the mode
--
-- v3 (docs/online-design.md 2.4) adds, all additively: gen, game, family,
-- nationalDex (the FR/LG gate reads it), wire = { mon = MonCodec version },
-- features, battleFingerprint, and the invite's nonce / a world's mapSet
-- when opts carries them.  A v2 peer ignores every one of them.
function Handshake.hello(game, mode, opts)
  local mods = Handshake.mods(game)
  local info = require("src.online.CompatRules").info(game)
  local features = {}
  for i, f in ipairs(Handshake.FEATURES) do features[i] = f end
  return {
    type = "hello",
    protocol = Handshake.PROTOCOL,
    name = game and game.save and game.save.player and game.save.player.name,
    mode = mode,
    engineVersion = Version.engine,
    apiVersion = Version.modApi,
    fingerprint = Fingerprint.compute(game and game.data, mods),
    linkModified = Handshake.linkModified(game),
    mods = mods,
    gen = info.gen,
    game = info.game,
    family = info.family,
    nationalDex = info.nationalDex,
    wire = { mon = Version.linkMonWire or 3 },
    features = features,
    battleFingerprint = Fingerprint.battle(game and game.data, mods),
    nonce = opts and opts.nonce or nil,
    mapSet = opts and opts.mapSet or nil,
  }
end

-- the features both hellos list (a v2 hello lists none: trade and battle,
-- the only two it knew)
function Handshake.features(localHello, remoteHello)
  local function set(h)
    local s = {}
    local list = h and h.features
    if type(list) ~= "table" then list = { "trade", "battle" } end
    for _, f in ipairs(list) do s[f] = true end
    return s
  end
  local a, b = set(localHello), set(remoteHello)
  local out = {}
  for _, f in ipairs(Handshake.FEATURES) do
    if a[f] and b[f] then out[#out + 1] = f end
  end
  for f in pairs(a) do
    local known = false
    for _, g in ipairs(Handshake.FEATURES) do if g == f then known = true end end
    if not known and b[f] then out[#out + 1] = f end
  end
  return out
end

-- the MonCodec version a hello speaks (nil: a v1/v2 peer, v2 packets)
function Handshake.monWire(hello)
  local w = type(hello) == "table" and type(hello.wire) == "table" and hello.wire.mon
  return tonumber(w)
end

local function major(semver)
  return tonumber(tostring(semver or ""):match("^(%d+)")) or 0
end

-- full        identical link surfaces: nothing to negotiate, lockstep is safe
-- vanilla_peer  an old build, and we are unmodified, so it is right about us
-- subset      both v2 (or v3 Gen 1/2) but the surfaces differ: negotiated
--             trade, no battle
-- family      v3, two games of one Gen 3+ family (E/FRLG, Pt/HGSS) or one
--             game with different data: trade with MonCodec v3 under the
--             CompatRules gates; battle only host-authoritative (WS5)
-- timecapsule v3, Gen 1 <-> Gen 2: trade only, Time Capsule rules
-- transfer    v3, Gen 3 -> 4 (Pal Park) or Gen 4 -> 5 (Poke Transfer): a
--             one-way gift from the older game to the newer one
--             (src/online/Transfer.lua TransferSession), never a swap
-- refused     an old build we would silently corrupt, a different engine,
--             a v2 peer on a Gen 3+ game, or two games that cannot link
local function decide(localHello, remoteHello)
  if not remoteHello or not remoteHello.protocol then
    if localHello.linkModified then
      return "refused", "peer_v1_modified"
    end
    -- a v1 peer predates every Gen 3+ game; its packets carry Gen 1/2 only
    if (tonumber(localHello.gen) or 1) >= 3 then
      return "refused", "peer_v2"
    end
    return "vanilla_peer", nil
  end
  if major(remoteHello.engineVersion) ~= major(localHello.engineVersion) then
    return "refused", "engine_mismatch"
  end
  if (tonumber(remoteHello.protocol) or 0) < 3 then
    -- v2 loses a Gen 3+ mon's personality, IVs, EVs and nature: refuse
    -- rather than corrupt it.  Gen 1/2 keep the v2 path verbatim.
    if (tonumber(localHello.gen) or 1) >= 3 then
      return "refused", "peer_v2"
    end
    if remoteHello.fingerprint == localHello.fingerprint then
      return "full", nil
    end
    return "subset", "fingerprint_mismatch"
  end
  local pair = require("src.online.CompatRules").pair(localHello, remoteHello)
  if pair.transfer then
    -- one way upward: Pal Park (Gen 3 -> 4) or Poke Transfer (4 -> 5)
    return "transfer", pair.transfer.route, pair
  end
  if not pair.trade then
    return "refused", pair.reason, pair
  end
  if pair.timeCapsule then
    return "timecapsule", "time_capsule", pair
  end
  if remoteHello.fingerprint == localHello.fingerprint then
    return "full", nil, pair
  end
  if (tonumber(localHello.gen) or 1) <= 2 then
    return "subset", "fingerprint_mismatch", pair
  end
  return "family", "fingerprint_mismatch", pair
end

-- The last decision, for the code that has no other way to learn it: the
-- current LinkState builds its TradeSession from the verdict alone, so
-- Protocol reads the peer's hello here (the per-mon gates, the MonCodec
-- version to speak).  Callers that hold both hellos pass them explicitly.
Handshake.session = nil

-- returns verdict, reason, pair (CompatRules.pair for v3 peers)
function Handshake.checkCompat(localHello, remoteHello)
  localHello = localHello or {}
  local verdict, reason, pair = decide(localHello, remoteHello)
  Handshake.session = { mine = localHello, theirs = remoteHello,
                        verdict = verdict, reason = reason, pair = pair }
  return verdict, reason, pair
end

-- only two v2 peers that agreed on a verdict may reject a mon outright; a v1
-- peer keeps the old substitute-a-move behaviour it was built against
function Handshake.strict(verdict)
  return verdict == "full" or verdict == "subset" or verdict == "family"
    or verdict == "timecapsule" or verdict == "transfer"
end

-- `family` (two games of one Gen 3+ family with different data) battles
-- host-authoritatively (WS5, src/online/LinkBattleModern.lua; the mode comes
-- from LinkBattle.modeFor)
function Handshake.battleAllowed(verdict)
  return verdict == "full" or verdict == "vanilla_peer" or verdict == "family"
    or verdict == nil
end

-- a transfer link is a one-way gift, not a trade
function Handshake.tradeAllowed(verdict)
  return verdict ~= "refused" and verdict ~= "transfer"
end

function Handshake.transferAllowed(verdict)
  return verdict == "transfer"
end

-- ------- incompatibility report

local function index(mods)
  local byId = {}
  for _, mod in ipairs(mods or {}) do byId[tostring(mod.id)] = mod end
  return byId
end

-- the two mod arrays diffed, so the screen can name the difference instead
-- of the old silent mid-battle draw
function Handshake.modDiff(localHello, remoteHello)
  local mine = index(localHello and localHello.mods)
  local theirs = index(remoteHello and remoteHello.mods)
  local onlyMine, onlyTheirs, differing = {}, {}, {}
  for id, mod in pairs(mine) do
    local peer = theirs[id]
    if not peer then
      onlyMine[#onlyMine + 1] = mod
    elseif tostring(peer.version) ~= tostring(mod.version) then
      differing[#differing + 1] = { id = id, mine = mod.version,
                                    theirs = peer.version }
    end
  end
  for id, mod in pairs(theirs) do
    if not mine[id] then onlyTheirs[#onlyTheirs + 1] = mod end
  end
  local byId = function(a, b) return tostring(a.id) < tostring(b.id) end
  table.sort(onlyMine, byId)
  table.sort(onlyTheirs, byId)
  table.sort(differing, byId)
  return { onlyMine = onlyMine, onlyTheirs = onlyTheirs, differing = differing }
end

local WIDTH = 19 -- characters that fit one 160px line at 8px per glyph

local function wrap(lines, text)
  while #text > WIDTH do
    local cut = text:sub(1, WIDTH + 1):match("^.*()%s")
    if not cut or cut <= 1 then cut = WIDTH + 1 end
    lines[#lines + 1] = text:sub(1, cut - 1)
    text = text:sub(cut + 1)
  end
  if #text > 0 then lines[#lines + 1] = text end
end

local function listMods(lines, heading, mods)
  if #mods == 0 then return end
  wrap(lines, heading)
  for i, mod in ipairs(mods) do
    if i > 3 then
      wrap(lines, ("and %d more."):format(#mods - 3))
      return
    end
    wrap(lines, (" %s %s"):format(tostring(mod.id):upper():sub(1, 12),
                                  tostring(mod.version or "?")))
  end
end

-- lines for the incompatibility screen: what differs, then what still works
function Handshake.describe(localHello, remoteHello, verdict, mode)
  local lines = {}
  local peer = (remoteHello and remoteHello.name) or "THEY"
  local _, reason = decide(localHello or {}, remoteHello)
  if verdict == "refused" and reason == "peer_v2" then
    -- v3: a Gen 3+ game against an older build
    wrap(lines, "The other game is")
    wrap(lines, "an older version.")
    wrap(lines, "Update the other")
    wrap(lines, "game to trade.")
    return lines
  end
  if verdict == "refused" and (reason == "cross_generation"
      or reason == "cross_family" or reason == "no_family") then
    wrap(lines, "These two games")
    wrap(lines, "can't link.")
    local theirs = remoteHello and remoteHello.game
    if type(theirs) == "string" and #theirs > 0 then
      wrap(lines, ("The other game is %s."):format(theirs:upper():sub(1, 12)))
    end
    return lines
  end
  if verdict == "refused" and reason == "cross_series" then
    wrap(lines, "That code is for")
    wrap(lines, "a game from another")
    wrap(lines, "series. It can't")
    wrap(lines, "link with POKéMON.")
    return lines
  end
  if verdict == "refused" and reason == "needs_national_dex" then
    wrap(lines, "PAL PARK needs")
    wrap(lines, "the NATIONAL DEX")
    wrap(lines, "in the DS game.")
    return lines
  end
  if verdict == "transfer" then
    local palPark = reason == "palpark"
    wrap(lines, palPark and "PAL PARK" or "POKé TRANSFER")
    wrap(lines, "One way only, to")
    wrap(lines, palPark and "the DS game." or "BLACK or WHITE.")
    wrap(lines, "It can't come back.")
    if mode == "battle" then
      wrap(lines, "Link battle isn't")
      wrap(lines, "possible here.")
    end
    return lines
  end
  if verdict == "timecapsule" then
    wrap(lines, "TIME CAPSULE")
    if mode == "battle" then
      wrap(lines, "Link battle isn't")
      wrap(lines, "possible through")
      wrap(lines, "the TIME CAPSULE.")
    else
      wrap(lines, "Only POKéMON and")
      wrap(lines, "moves both games")
      wrap(lines, "know can be")
      wrap(lines, "traded.")
    end
    return lines
  end
  if verdict == "family" and remoteHello and remoteHello.game ~= nil
     and localHello and remoteHello.game ~= localHello.game then
    wrap(lines, "A different game")
    wrap(lines, "of the same")
    wrap(lines, "series.")
    if mode == "battle" then
      -- a family battle runs host-authoritatively (WS5, LinkBattleModern)
      wrap(lines, "Link battle works:")
      wrap(lines, "the host's game")
      wrap(lines, "runs the battle.")
    else
      wrap(lines, "Trading works.")
    end
    return lines
  end
  if verdict == "refused" then
    if not (remoteHello and remoteHello.protocol) then
      wrap(lines, "The other game is")
      wrap(lines, "an older version")
      wrap(lines, "with no mods.")
      wrap(lines, "Your mods can't")
      wrap(lines, "link with it.")
    else
      wrap(lines, "The two games are")
      wrap(lines, "different engine")
      wrap(lines, "versions.")
    end
    return lines
  end
  wrap(lines, "Your games differ.")
  local diff = Handshake.modDiff(localHello, remoteHello)
  listMods(lines, peer .. " has:", diff.onlyTheirs)
  listMods(lines, "You have:", diff.onlyMine)
  for i, row in ipairs(diff.differing) do
    if i > 2 then break end
    wrap(lines, ("%s %s vs %s"):format(tostring(row.id):upper():sub(1, 8),
                                       tostring(row.mine), tostring(row.theirs)))
  end
  if #diff.onlyMine == 0 and #diff.onlyTheirs == 0 and #diff.differing == 0 then
    wrap(lines, "The game data is")
    wrap(lines, "not the same.")
  end
  if mode == "battle" and verdict == "family" then
    -- same family, different data: host-authoritative (WS5)
    wrap(lines, "Link battle works:")
    wrap(lines, "the host's game")
    wrap(lines, "runs the battle.")
  elseif mode == "battle" then
    wrap(lines, "Link battle needs")
    wrap(lines, "the same mods.")
  else
    wrap(lines, "Trading is limited")
    wrap(lines, "to shared POKéMON.")
  end
  return lines
end

return Handshake
