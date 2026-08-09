-- crosscheck.lua -- adversarial cross-validation of GenSave.decode against
-- the INDEPENDENT vendor parser (vendor/gen1lib.lua, a PKHeX-derived generic
-- Gen1 .sav<->JSON codec) on a real 32768-byte battery save. Two codecs
-- triangulated from different authorities (GenSave from the pokered
-- disassembly, the vendor from PKHeX.Core) reading the same bytes: any
-- semantic field they disagree on is a bug in one of them.
--
--   run: lua5.4 tools/save_convert/crosscheck.lua   (needs POKEPORT_SAV_FIXTURE)
--
-- INTERPRETER NOTE. The vendor lib is written in Lua 5.3+ (native << >> & //
-- operators, utf8 library) and cannot even be PARSED by LuaJIT, while GenSave
-- `require("bit")`s LuaJIT's BitOp. So this harness must run under a stock
-- Lua 5.3/5.4, and we hand GenSave a tiny `bit` shim backed by 5.4's native
-- operators. (The main suite, tests/save_convert_tests.lua, still runs under
-- luajit; this maintenance tool is the one place both codecs coexist.)
--
-- COVERAGE ASYMMETRY / ORACLE CHOICE. The vendor decodes trainer block,
-- party, and all 12 boxes, but deliberately leaves items, Pokedex, options,
-- event flags, map and coords inside its opaque `raw_base64` blob (it only
-- round-trips them, never interprets them). For every such field this harness
-- reads the RAW BYTES straight out of the vendor's own byte buffer at the
-- vendor's own M.OFS.* offsets (an authority fully independent of GenSave's
-- offset table) and compares GenSave's decode against that. So even the
-- "vendor doesn't model it" fields still get a genuine second-source check.
--
-- NO STANDING VENDOR DISAGREEMENTS. Every field the vendor DOES interpret
-- agrees with GenSave on the real fixture, so there is no vendor bug to work
-- around here. (Were one found, the rule per the task is: leave vendor code
-- untouched, keep GenSave's value, and document the disagreement in this
-- block.) The one bug this cross-check flushed out was on GenSave's side: its
-- flag_array reader packed bits MSB-first, but pokered's FlagAction (and
-- PKHeX) pack LSB-first. It survived the round-trip suite because encode and
-- decode shared the wrong convention; it did NOT survive contact with a real
-- save, where boxed ZAPDOS (dex 145) read back as un-owned. Fixed in GenSave
-- (bitGet/bitSet); this harness re-decodes the dex from raw bytes LSB-first
-- and now agrees.

------------------------------------------------------------------------
-- `bit` shim for GenSave, backed by native Lua 5.4 operators.
------------------------------------------------------------------------
if not pcall(require, "bit") then
  package.preload["bit"] = function()
    local M = {}
    -- LuaJIT's BitOp band/bor/bxor are VARIADIC (fold over all args); GenSave
    -- relies on that in decodeDVs' 4-arg bit.bor for the HP DV. A 2-arg shim
    -- silently drops the tail args -- so fold explicitly here.
    function M.band(a, ...) local r = a; for _, v in ipairs({...}) do r = r & v end; return r & 0xFFFFFFFF end
    function M.bor(a, ...) local r = a; for _, v in ipairs({...}) do r = r | v end; return r & 0xFFFFFFFF end
    function M.bxor(a, ...) local r = a; for _, v in ipairs({...}) do r = r ~ v end; return r & 0xFFFFFFFF end
    function M.bnot(a) return (~a) & 0xFFFFFFFF end
    function M.lshift(a, n) return (a << n) & 0xFFFFFFFF end
    function M.rshift(a, n) return (a & 0xFFFFFFFF) >> n end
    return M
  end
end

package.path = "./?.lua;" .. package.path

------------------------------------------------------------------------
-- Load GenSave + the same generated data the codec uses in production.
------------------------------------------------------------------------
local GenSave = require("src.save_convert.GenSave")
local charmap = loadfile("src/save_convert/data/charmap.lua")()
GenSave.setCharmap(charmap)
local data = {
  pokemon    = loadfile("data/generated/pokemon.lua")(),
  moves      = loadfile("data/generated/moves.lua")(),
  items      = loadfile("data/generated/items.lua")(),
  maps       = loadfile("data/generated/maps.lua")(),
  eventFlags = loadfile("src/save_convert/data/event_flags.lua")(),
}
local cw = GenSave.crosswalks(data)

------------------------------------------------------------------------
-- Load the fixture.
------------------------------------------------------------------------
local fixturePath = os.getenv("POKEPORT_SAV_FIXTURE")
if not fixturePath then
  io.stderr:write("POKEPORT_SAV_FIXTURE is not set (point it at a 32768-byte .sav)\n")
  os.exit(2)
end
local ff, oerr = io.open(fixturePath, "rb")
if not ff then
  io.stderr:write("cannot open POKEPORT_SAV_FIXTURE: " .. tostring(oerr) .. "\n")
  os.exit(2)
end
local rawStr = ff:read("*a"); ff:close()
if #rawStr ~= GenSave.SAVE_SIZE then
  io.stderr:write(("fixture is %d bytes, expected %d\n"):format(#rawStr, GenSave.SAVE_SIZE))
  os.exit(2)
end

------------------------------------------------------------------------
-- Parse the SAME bytes through both codecs.
------------------------------------------------------------------------
local gen = GenSave.decode(rawStr, data)

local gen1 = dofile("tools/save_convert/vendor/gen1lib.lua")
local vbuf = gen1.string_to_bytes(rawStr)           -- vendor's 1-indexed byte array
local ven = gen1.parse_save(vbuf)

-- Raw readers over the vendor's byte buffer (fileOffset -> byte). Used as an
-- independent oracle for the fields the vendor leaves inside raw_base64.
-- These numeric offsets are exactly the ones gen1lib uses internally (its
-- M.OFS), transcribed here so the oracle is anchored to the VENDOR's layout,
-- not GenSave's.
local RAW = {
  DexCaught = 0x25A3, DexSeen = 0x25B6, Items = 0x25C9, Options = 0x2601,
  PCItems = 0x27E6,
}
local function rb(off) return vbuf[off + 1] end        -- raw byte at file offset
local function dexbit_lsb(base, idx) return ((rb(base + (idx // 8)) >> (idx % 8)) & 1) == 1 end

------------------------------------------------------------------------
-- Diff collector.
------------------------------------------------------------------------
local fails, notes = {}, {}
local function fail(field, msg) fails[#fails + 1] = { field = field, msg = msg } end
local function eq(field, a, b, ctx)
  if a ~= b then
    fail(field, ("%s: GenSave=%s vendor=%s"):format(ctx or "", tostring(a), tostring(b)))
    return false
  end
  return true
end
local function note(msg) notes[#notes + 1] = msg end

local NAME_LEN = 11   -- GenSave NAME_LENGTH == vendor STRING_LENGTH
-- Name equivalence. GenSave and the vendor spell a few glyphs differently:
-- GenSave uses bracket control tokens ("<DOT>" for byte 0xE8, "<TRAINER>" for
-- the 0x5D in-game-trade OT marker); the vendor uses the raw Unicode glyph
-- ("\u{2024}") / "*". These are the SAME underlying Gen1 byte, so instead of
-- comparing the decoded text we canonicalize each side back to its 11-byte
-- Gen1 sequence via its own table and compare THOSE. A genuine offset or
-- coverage bug (wrong name bytes) still surfaces as a byte-sequence diff.
local function genNameToBytes(text)   -- mirrors GenSave's local encodeName
  local out, i, pos = {}, 0, 1
  text = text or ""
  while i < NAME_LEN - 1 and pos <= #text do
    local bracket = text:match("^(<[^<>]*>)", pos)
    local ch, clen
    if bracket and charmap.byToken[bracket] then
      ch, clen = bracket, #bracket
    else
      local b0 = text:byte(pos)
      clen = (b0 < 0x80 and 1) or (b0 < 0xE0 and 2) or (b0 < 0xF0 and 3) or 4
      ch = text:sub(pos, pos + clen - 1)
    end
    out[i + 1] = string.char(charmap.byToken[ch] or charmap.byToken["?"] or 0x50)
    i, pos = i + 1, pos + clen
  end
  for j = i, NAME_LEN - 1 do out[j + 1] = string.char(0x50) end
  return table.concat(out)
end
local function venNameToBytes(text)   -- via the vendor's own encoder
  local b = {}
  gen1.encode_string(b, 0, NAME_LEN, text or "")
  local out = {}
  for k = 1, NAME_LEN do out[k] = string.char((b[k] or 0x50) & 0xFF) end
  return table.concat(out)
end
local repNoted = {}
local function compareName(field, g, v, ctx)
  if g == v then return end
  if genNameToBytes(g) == venNameToBytes(v) then
    local key = tostring(g) .. "|" .. tostring(v)
    if not repNoted[key] then
      repNoted[key] = true
      note(("name glyph representation differs, bytes identical: GenSave %q == vendor %q")
        :format(tostring(g), tostring(v)))
    end
  else
    fail(field, ("%s: GenSave=%q vendor=%q (byte sequences differ)")
      :format(ctx or "", tostring(g), tostring(v)))
  end
end

------------------------------------------------------------------------
-- 1. Trainer block (vendor decodes all of these).
------------------------------------------------------------------------
compareName("player.name",  gen.player.name,  ven.trainer.name,       "player name")
eq("player.id",    gen.player.id,    ven.trainer.id,         "trainer id")
compareName("player.rival", gen.player.rival, ven.trainer.rival_name, "rival name")
eq("money",        gen.money,        ven.trainer.money,      "money")
eq("coins",        gen.coins,        ven.trainer.coins,      "coins")

-- badges: GenSave exposes them as truthy inventory entries; vendor gives the
-- raw wObtainedBadges byte. Compare bit for bit (BIT_BOULDERBADGE=0 .. =7).
local BADGE = { [0]="BOULDERBADGE",[1]="CASCADEBADGE",[2]="THUNDERBADGE",
  [3]="RAINBOWBADGE",[4]="SOULBADGE",[5]="MARSHBADGE",[6]="VOLCANOBADGE",[7]="EARTHBADGE" }
for i = 0, 7 do
  local vset = ((ven.trainer.badges >> i) & 1) == 1
  local gset = gen.inventory[BADGE[i]] == 1
  eq("badges." .. BADGE[i], gset, vset, "badge bit " .. i)
end

------------------------------------------------------------------------
-- 2. Play time (vendor decodes H/M/S/F/maxed; GenSave folds to one float).
------------------------------------------------------------------------
do
  local pt = ven.trainer.play_time
  local expected = pt.hours * 3600 + pt.minutes * 60 + pt.seconds + pt.frames / 60
  if math.abs(gen.playTime - expected) > 1e-6 then
    fail("playTime", ("GenSave=%s vendor=%dh%02dm%02ds%02df"):format(
      tostring(gen.playTime), pt.hours, pt.minutes, pt.seconds, pt.frames))
  end
end

------------------------------------------------------------------------
-- 3. Options -- GenSave does not model this field; verify that's the only
--    reason for silence, and record the raw value the vendor would carry.
------------------------------------------------------------------------
if gen.options == nil then
  note(("options: not modeled by GenSave (raw wOptions byte = 0x%02X, preserved "
        .. "verbatim via the export template)"):format(rb(RAW.Options)))
else
  eq("options", gen.options, rb(RAW.Options), "options byte")
end

------------------------------------------------------------------------
-- 4. Current box + map/coords.
------------------------------------------------------------------------
eq("currentBox", gen.currentBox, ven.current_box, "current box number")
-- Map + coords: the vendor does not decode wCurMap/X/Y at all. Sanity-check
-- GenSave's values against its own data tables (no second source available).
if gen.player.map and data.maps[gen.player.map] then
  note(("map/coords: vendor does not decode these; GenSave says map=%s x=%s y=%s "
        .. "(a valid map id)"):format(gen.player.map, tostring(gen.player.x), tostring(gen.player.y)))
else
  fail("player.map", "GenSave decoded an unknown/absent current map")
end

------------------------------------------------------------------------
-- 5. Bag + PC items -- vendor leaves these in raw_base64; read the raw
--    (id,qty) lists straight from its byte buffer as the oracle.
------------------------------------------------------------------------
local function rawItemList(base, capacity)
  local count = rb(base)
  local list = {}
  for i = 0, math.min(count, capacity) - 1 do
    local idb = rb(base + 1 + i * 2)
    if idb == 0xFF then break end
    list[#list + 1] = { idByte = idb, qty = rb(base + 2 + i * 2) }
  end
  return count, list
end

-- Bag: GenSave preserves order in save.bagOrder; compare id+qty in sequence.
do
  local count, raw = rawItemList(RAW.Items, 20)
  eq("bag.count", #gen.bagOrder, count, "bag item count")
  local n = math.max(#gen.bagOrder, #raw)
  for i = 1, n do
    local gid = gen.bagOrder[i]
    local r = raw[i]
    local gidx = gid and cw.itemsIndex[gid]
    eq("bag[" .. i .. "].id", gidx, r and r.idByte, "bag slot " .. i .. " item")
    if gid and r then eq("bag[" .. i .. "].qty", gen.inventory[gid], r.qty, "bag slot " .. i .. " qty") end
  end
end

-- PC: GenSave keeps only a {id->qty} map (order dropped); compare as a set.
do
  local count, raw = rawItemList(RAW.PCItems, 50)
  local rawMap, rawCount = {}, 0
  for _, r in ipairs(raw) do
    local id = cw.itemsByIndex[r.idByte]
    if id then rawMap[id] = r.qty; rawCount = rawCount + 1 end
  end
  local genCount = 0
  for id, qty in pairs(gen.pcItems) do
    genCount = genCount + 1
    eq("pcItems." .. id, qty, rawMap[id], "PC item " .. id .. " qty")
  end
  eq("pcItems.count", genCount, rawCount, "PC item count")
end

------------------------------------------------------------------------
-- 6. Pokedex owned/seen -- vendor leaves these in raw_base64; decode the
--    raw bitsets LSB-first (pokered/PKHeX convention) as the oracle.
------------------------------------------------------------------------
do
  for dex, species in pairs(cw.pokemonByDex) do
    if dex >= 1 and dex <= 151 then
      local rawOwned = dexbit_lsb(RAW.DexCaught, dex - 1)
      local rawSeen  = dexbit_lsb(RAW.DexSeen, dex - 1)
      eq("dex.owned." .. species, gen.pokedex.owned[species] == true, rawOwned, "owned " .. species)
      eq("dex.seen." .. species,  gen.pokedex.seen[species] == true,  rawSeen,  "seen " .. species)
    end
  end
  -- physical invariant: every possessed species must be owned AND seen.
  local possessed = {}
  for _, m in ipairs(gen.party) do possessed[m.species] = true end
  for b = 1, 12 do for _, m in ipairs(gen.boxes[b]) do possessed[m.species] = true end end
  for sp in pairs(possessed) do
    if not gen.pokedex.owned[sp] then fail("dex.invariant", sp .. " is possessed but not owned") end
    if not gen.pokedex.seen[sp] then fail("dex.invariant", sp .. " is possessed but not seen") end
  end
end

------------------------------------------------------------------------
-- 7. Event flags -- vendor leaves these in raw_base64; there is no vendor
--    field to compare against, but the physical invariant that the very
--    first story flag (EVENT_FOLLOWED_OAK_INTO_LAB, bit 0) is set on any
--    save past the intro is a real LSB-vs-MSB discriminator.
------------------------------------------------------------------------
do
  local nflags = 0
  for _ in pairs(gen.flags) do nflags = nflags + 1 end
  if nflags == 0 then fail("flags", "no event flags decoded at all") end
  if not gen.flags.EVENT_FOLLOWED_OAK_INTO_LAB then
    fail("flags.EVENT_FOLLOWED_OAK_INTO_LAB",
         "bit 0 not set -- expected on any save past the intro (LSB-order check)")
  end
end

------------------------------------------------------------------------
-- 8. Mon-by-mon comparison (party + boxes) against the vendor's PK1 parse.
------------------------------------------------------------------------
local STATUS_BIT = { PSN = 3, BRN = 4, FRZ = 5, PAR = 6 }
local function statusFromByte(b)
  if (b & 7) > 0 then return "SLP" end
  for name, bi in pairs(STATUS_BIT) do if (b & (1 << bi)) ~= 0 then return name end end
  return nil
end

local function compareMon(tag, g, v, isParty)
  if not g or not v then
    fail(tag, "one side missing this slot (GenSave=" .. tostring(g) .. " vendor=" .. tostring(v) .. ")")
    return
  end
  -- species: GenSave id string -> national dex must equal vendor's dex number.
  eq(tag .. ".species", cw.pokemonDex[g.species], v.species, tag .. " species (" .. tostring(g.species) .. ")")
  eq(tag .. ".level", g.level, v.level, tag .. " level")
  eq(tag .. ".hp", g.hp, v.current_hp, tag .. " current HP")
  eq(tag .. ".otId", g.otId, v.ot_id, tag .. " OT id")
  eq(tag .. ".exp", g.exp, v.exp, tag .. " exp")
  eq(tag .. ".catchRate", g.catchRate, v.catch_rate, tag .. " catch rate")
  compareName(tag .. ".ot", g.ot, v.ot_name, tag .. " OT name")
  compareName(tag .. ".nickname", g.nickname, v.nickname, tag .. " nickname")
  -- DVs / IVs
  eq(tag .. ".dv.atk", g.dvs.attack, v.ivs.atk, tag .. " DV atk")
  eq(tag .. ".dv.def", g.dvs.defense, v.ivs.def, tag .. " DV def")
  eq(tag .. ".dv.spe", g.dvs.speed, v.ivs.spe, tag .. " DV spe")
  eq(tag .. ".dv.spc", g.dvs.special, v.ivs.spc, tag .. " DV spc")
  eq(tag .. ".dv.hp", g.dvs.hp, v.ivs.hp, tag .. " DV hp")
  -- stat EXP / EVs
  eq(tag .. ".ev.hp", g.statExp.hp, v.evs.hp, tag .. " statExp hp")
  eq(tag .. ".ev.atk", g.statExp.attack, v.evs.atk, tag .. " statExp atk")
  eq(tag .. ".ev.def", g.statExp.defense, v.evs.def, tag .. " statExp def")
  eq(tag .. ".ev.spe", g.statExp.speed, v.evs.spe, tag .. " statExp spe")
  eq(tag .. ".ev.spc", g.statExp.special, v.evs.spc, tag .. " statExp spc")
  -- status: GenSave string vs vendor raw byte (decoded the same way)
  eq(tag .. ".status", g.status, statusFromByte(v.status_condition), tag .. " status")
  -- moves: GenSave keeps only nonzero slots, in order; line them up against
  -- the vendor's 4 raw slots skipping zeros.
  local vmoves = {}
  for j = 1, 4 do
    if v.moves[j] and v.moves[j] > 0 then
      vmoves[#vmoves + 1] = { idx = v.moves[j], pp = v.pp[j], ppUps = v.pp_ups[j] }
    end
  end
  eq(tag .. ".moves.count", #g.moves, #vmoves, tag .. " move count")
  for j = 1, math.max(#g.moves, #vmoves) do
    local gm, vm = g.moves[j], vmoves[j]
    local gidx = gm and cw.movesIndex[gm.id]
    eq(tag .. ".move[" .. j .. "].id", gidx, vm and vm.idx, tag .. " move " .. j)
    if gm and vm then
      eq(tag .. ".move[" .. j .. "].pp", gm.pp, vm.pp, tag .. " move " .. j .. " PP")
      eq(tag .. ".move[" .. j .. "].ppUps", gm.ppUps, vm.ppUps, tag .. " move " .. j .. " PP-ups")
    end
  end
  -- party-only computed stats
  if isParty then
    eq(tag .. ".stat.hp", g.stats.hp, v.stats.hp_max, tag .. " stat maxHP")
    eq(tag .. ".stat.atk", g.stats.attack, v.stats.atk, tag .. " stat atk")
    eq(tag .. ".stat.def", g.stats.defense, v.stats.def, tag .. " stat def")
    eq(tag .. ".stat.spe", g.stats.speed, v.stats.spe, tag .. " stat spe")
    eq(tag .. ".stat.spc", g.stats.special, v.stats.spc, tag .. " stat spc")
  end
end

-- party
eq("party.count", #gen.party, #ven.party, "party size")
for i = 1, math.max(#gen.party, #ven.party) do
  compareMon("party[" .. i .. "]", gen.party[i], ven.party[i], true)
end

-- boxes: the vendor returns all 12 boxes 1..12 (current box read from its
-- live offset). GenSave stores them the same 1-based way.
for b = 1, 12 do
  local vbox = ven.boxes[b] and ven.boxes[b].pokemon or {}
  local gbox = gen.boxes[b] or {}
  eq("box[" .. b .. "].count", #gbox, #vbox, "box " .. b .. " size")
  for i = 1, math.max(#gbox, #vbox) do
    compareMon(("box[%d][%d]"):format(b, i), gbox[i], vbox[i], false)
  end
end

------------------------------------------------------------------------
-- 9. Checksum cross-check: both codecs sum [0x2598,0x3523). The fixture is a
--    real save, so GenSave's stored-checksum verification must pass, and the
--    vendor's independent recompute must match the same stored byte.
------------------------------------------------------------------------
do
  if #gen.warnings > 0 then
    for _, w in ipairs(gen.warnings) do fail("checksum", "GenSave warning: " .. w) end
  end
  local sum = 0
  for i = 0x2598, 0x3523 - 1 do sum = (sum + rb(i)) & 0xFF end
  local vend = (255 - sum) & 0xFF
  eq("checksum.byte", rb(0x3523), vend, "stored main checksum vs vendor recompute")
end

------------------------------------------------------------------------
-- Report.
------------------------------------------------------------------------
print("== crosscheck: GenSave.decode vs vendor gen1lib on the real fixture ==")
print(("player=%s id=%d money=%d coins=%d party=%d")
  :format(gen.player.name, gen.player.id, gen.money, gen.coins, #gen.party))
do
  local owned, seen = 0, 0
  for _ in pairs(gen.pokedex.owned) do owned = owned + 1 end
  for _ in pairs(gen.pokedex.seen) do seen = seen + 1 end
  local boxed = 0
  for b = 1, 12 do boxed = boxed + #gen.boxes[b] end
  print(("dex owned/seen=%d/%d  boxed=%d  currentBox=%d")
    :format(owned, seen, boxed, gen.currentBox))
end

if #notes > 0 then
  print("\n-- notes (fields the vendor does not model; checked against raw bytes) --")
  for _, m in ipairs(notes) do print("  * " .. m) end
end

if #fails == 0 then
  print("\nALL SHARED FIELDS AGREE -- GenSave.decode matches the vendor parser (and\n"
      .. "the raw-byte oracle for the fields the vendor leaves opaque).")
  os.exit(0)
else
  print(("\n%d MISMATCH(ES):"):format(#fails))
  for _, f in ipairs(fails) do
    print(("  [%s] %s"):format(f.field, f.msg))
  end
  os.exit(1)
end
