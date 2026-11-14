-- PAL PARK: Platinum's on Route 221, HeartGold / SoulSilver's in Fuchsia City.
--
-- Two halves, as on the cartridge:
--
--   MIGRATION (the main menu's MIGRATE FROM ..., src/ui/Gen4Migrate.lua): six
--   Pokemon out of a Generation III game's PC -- here, one of this port's own
--   Ruby / Sapphire / Emerald / FireRed / LeafGreen saves -- into the DS save's
--   transfer storage (`MigratedPokemon`). The rules are the cartridge's: the
--   National Pokedex, an empty transfer storage, exactly six, no Egg and
--   nothing knowing an HM move, and once a day per Game Pak; the six leave the
--   Game Pak for good.
--
--   THE CATCHING SHOW (catching_show.c, scrcmd_catching_show.c): the six are
--   loose in the park, one in each kind of place its species lives; every
--   5-14 steps in tall grass or on water is a roll for whichever of the
--   uncaught ones live in that quadrant's grass or water, a Park Ball each
--   (one throw catches), and the score is catching + time + type points.
--   The lobby's worker then boxes all six.
--
-- `save.gen4PalPark`: { transfer = { mon x6 }, migrated = { [source] = os.time() },
--   inPark = the system flag, show = the running show }.

local P = {}

P.MONS = 6
P.NO_ENCOUNTER = 20          -- WEIGHT_NO_ENCOUNTER
P.DIFFERENT_TYPE_BONUS = 200 -- a catch sharing no type with the one before
P.DISTINCT_TYPE_BONUS = 50   -- each type among the six
P.MAX_SECONDS = 1000
P.POINTS_PER_SECOND = 2
P.WATER_BASE = 4             -- PAL_PARK_AREA_LAND_END - 1: water areas follow land
P.ONCE_PER = 24 * 60 * 60    -- PalParkTransfer_GetSecondsSinceLastTransfer
-- HM moves a migrating Pokemon may not know (the Game Pak's eight)
P.HM_MOVES = { [15] = true, [19] = true, [57] = true, [70] = true,
               [127] = true, [148] = true, [249] = true, [291] = true }
P.GEN3_VERSIONS = { "ruby", "sapphire", "emerald", "firered", "leafgreen" }

local function rand(n) return love and love.math and love.math.random(0, n - 1) or math.random(0, n - 1) end

function P.store(save)
  if type(save) ~= "table" then return nil end
  save.gen4PalPark = save.gen4PalPark or {}
  local st = save.gen4PalPark
  st.transfer = st.transfer or {}
  st.migrated = st.migrated or {}
  return st
end

-- GetPalParkTransferMonCount
function P.count(save)
  local st = P.store(save)
  local n = 0
  for i = 1, P.MONS do if st and st.transfer[i] then n = n + 1 end end
  return n
end

function P.inPark(save)
  return save and save.gen4PalPark and save.gen4PalPark.inPark == true or false
end

-- the species record (Gen4PalParkData), or nil
function P.species(data, species)
  local rec = data and data.gen4_pal_park
  local sp = rec and rec.species
  return sp and sp[tonumber(species) or -1] or nil
end

local function typesOf(data, mon)
  local def = data and data.pokemon and data.pokemon[mon.species]
  local t = def and (def.types or { def.type1, def.type2 }) or {}
  local a = t[1] or "NONE"
  return a, t[2] or a
end

-- ---------------------------------------------------------------------------
-- the show
-- ---------------------------------------------------------------------------

-- CatchingShow_Start: each Pokemon's area, rarity, points and types; the
-- catch order cleared; the step count; the clock
function P.start(game)
  local save, data = game.save, game.data
  local st = P.store(save)
  local show = { pokemon = {}, order = {}, start = os.time(), timePoints = 0 }
  for i = 1, P.MONS do
    local mon = st.transfer[i]
    local rec = mon and P.species(data, mon.species) or {}
    local area = 0
    if (rec.land or 0) ~= 0 then area = rec.land
    elseif (rec.water or 0) ~= 0 then area = P.WATER_BASE + rec.water end
    local t1, t2 = typesOf(data, mon or {})
    show.pokemon[i] = { area = area, rarity = rec.rarity or 0, points = rec.points or 0,
                        type1 = t1, type2 = t2 }
    show.order[i] = 0
  end
  st.show = show
  P.resetSteps(show)
  return show
end

-- CatchingShow_ClearState (HGSS's PalParkAction 2): the catch order only
function P.clearState(game)
  local st = P.store(game.save)
  if st.show then for i = 1, P.MONS do st.show.order[i] = 0 end end
end

-- CatchingShow_End: what the time is worth, at the moment it ends
function P.finish(game)
  local st = P.store(game.save)
  local show = st.show
  if not show then return end
  local elapsed = os.time() - (show.start or os.time())
  show.timePoints = elapsed < P.MAX_SECONDS
                    and (P.MAX_SECONDS - elapsed) * P.POINTS_PER_SECOND or 0
  show.ended = true
  pcall(function()
    local R = require("src.pokemon.Gen4GameRecords")
    R.score(game.save, R.EVENT.FINISHED_CATCHING_SHOW)
  end)
end

function P.resetSteps(show) show.steps = rand(10) + 5 end

function P.caughtCount(show)
  local n = 0
  for i = 1, P.MONS do if (show and show.order[i] or 0) ~= 0 then n = n + 1 end end
  return n
end

-- FieldSystem_GetParkBallCount
function P.parkBalls(save)
  local st = P.store(save)
  return P.MONS - P.caughtCount(st and st.show)
end

-- GetEncounterArea: the quadrant (x and y against 32), and grass or water
function P.areaAt(map, x, y)
  local quadrant = (x < 32 and 0 or 1) + (y < 32 and 0 or 2)
  if map.isGrassCell and map:isGrassCell(x, y) then return 1 + quadrant end
  if map.isWaterCell and map:isWaterCell(x, y) then return 1 + P.WATER_BASE + quadrant end
  return 0
end

-- TryStartEncounter: the uncaught in this area, weighted by rarity, behind a
-- no-encounter bucket of 20. -> the transfer index, or nil
function P.roll(show, area, rng)
  if not show or area == 0 then return nil end
  rng = rng or rand
  local total = 0
  for i = 1, P.MONS do
    local p = show.pokemon[i]
    if show.order[i] == 0 and p and p.area == area then total = total + p.rarity end
  end
  if total == 0 then return nil end
  local pick = rng(total + P.NO_ENCOUNTER)
  if pick < P.NO_ENCOUNTER then return nil end
  pick = pick - P.NO_ENCOUNTER
  for i = 1, P.MONS do
    local p = show.pokemon[i]
    if show.order[i] == 0 and p and p.area == area then
      if pick < p.rarity then return i end
      pick = pick - p.rarity
    end
  end
  return nil
end

-- CatchingShow_CheckWildEncounter, from the overworld's step: true when a
-- battle was started (the ordinary encounter check is then skipped)
function P.stepEncounter(ow)
  local G = package.loaded["src.core.Game"]
  local save = G and G.save
  if not P.inPark(save) then return false end
  local st = P.store(save)
  local show = st.show
  if not show or show.ended then return true end
  show.steps = (show.steps or 1) - 1
  if show.steps > 0 then return true end
  P.resetSteps(show)
  local p = ow.player
  local index = P.roll(show, P.areaAt(ow.map, p.cellX, p.cellY))
  if not index then return true end
  P.battle(ow, index)
  return true
end

local function copy(t)
  local Ser = require("src.core.SaveSerializer")
  local ok, out = pcall(function() return Ser.decode(Ser.encode(t)) end)
  return ok and out or t
end

-- FieldSystem_SetupCatchingShowEncounter / Encounter_NewVsPalParkTransfer
function P.battle(ow, index)
  local G = package.loaded["src.core.Game"]
  local st = P.store(G.save)
  local mon = st.transfer[index]
  if not mon then return false end
  local BattleState = require("src.battle.BattleState")
  local battle = require("src.runmodes.RunHooks").quiet(BattleState.newWild, G, mon.species, mon.level or 1)
  battle.enemy = BattleState.makeBattler(G.data, copy(mon), false)
  battle:makeSafari({ balls = P.parkBalls(G.save), palPark = true })
  battle.palPark = { index = index }
  battle.onFinish = function(result)
    -- UpdateBattleResultInternal: a catch is numbered in the order it came
    if result == "caught" and st.show then
      st.show.order[index] = P.caughtCount(st.show) + 1
    end
    ow:afterBattle(result, battle)
    -- the last ball: the map's own script 3 (ScriptManager_Change(task, 3))
    if P.parkBalls(G.save) == 0 then P.runMapScript(ow, 3) end
  end
  ow:pushBattle(battle)
  return true
end

function P.runMapScript(ow, id)
  local G = package.loaded["src.core.Game"]
  local def = ow.map and ow.map.def
  local ms = G and G.data and G.data.map_scripts
  local entry = def and ms and ((ms.maps and ms.maps[def.id]) or ms[def.id])
  local label = entry and entry.entries and entry.entries[id]
  local rows = label and require("src.script.Gen4ScriptVM").compile(G.data, label)
  if not rows then return false end
  if ow.queueScript then ow:queueScript(rows, { mapId = def.id })
  elseif ow.runner then ow.runner:run(rows, { mapId = def.id }) end
  return true
end

-- the three scores (CalcCatchingShowPoints 0..3)
function P.catchingPoints(save)
  local show = P.store(save).show
  local n = 0
  for i = 1, P.MONS do n = n + ((show and show.pokemon[i] or {}).points or 0) end
  return n
end

function P.timePoints(save)
  local show = P.store(save).show
  return show and show.timePoints or 0
end

-- CalculateTypePoints: +200 for each catch sharing no type with the one before
-- it, then +50 for each type among them
function P.typePoints(save)
  local show = P.store(save).show
  if not show then return 0 end
  local total, seen, prev1, prev2 = 0, {}, nil, nil
  for n = 1, P.MONS do
    for j = 1, P.MONS do
      if show.order[j] == n then
        local p = show.pokemon[j]
        if n ~= 1 and prev1 ~= p.type1 and prev1 ~= p.type2
           and prev2 ~= p.type1 and prev2 ~= p.type2 then
          total = total + P.DIFFERENT_TYPE_BONUS
        end
        prev1, prev2 = p.type1, p.type2
        seen[p.type1], seen[p.type2] = true, true
        break
      end
    end
  end
  for _ in pairs(seen) do total = total + P.DISTINCT_TYPE_BONUS end
  return total
end

function P.points(save, category)
  category = tonumber(category) or 3
  if category == 0 then return P.catchingPoints(save) end
  if category == 1 then return P.timePoints(save) end
  if category == 2 then return P.typePoints(save) end
  return P.catchingPoints(save) + P.timePoints(save) + P.typePoints(save)
end

-- MoveCatchingShowMonsToPCBoxes: all six into the PC, registered as caught
function P.moveToBoxes(game)
  local st = P.store(game.save)
  local Boxes = require("src.pokemon.Boxes")
  local BattleState = require("src.battle.BattleState")
  for i = 1, P.MONS do
    local mon = st.transfer[i]
    if mon then
      mon.metLocation = BattleState.metHere(game) or mon.metLocation
      mon.metLevel = mon.level
      require("src.pokemon.Gen4Origin").stamp(game, mon, "met", mon.metLocation)
      Boxes.deposit(game.save, mon)
      pcall(BattleState.markOwned, game, mon.species)
      st.transfer[i] = nil
    end
  end
  st.show = nil
end

-- ---------------------------------------------------------------------------
-- migration
-- ---------------------------------------------------------------------------

local function norm(s) return (tostring(s or ""):upper():gsub("[^%w]", "")) end

-- a name-keyed lookup over a Gen 4 table (items, moves): normalised name -> id
local function byName(tbl)
  local out = {}
  for id, def in pairs(tbl or {}) do
    if type(id) == "number" and type(def) == "table" and def.name then
      out[norm(def.name)] = out[norm(def.name)] or id
    end
  end
  return out
end

-- the source game's records, read off its own cache (WalkerDelivery's way)
function P.sourceData(version)
  local Art = require("src.pokewalker.WalkerArt")
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  local out = {}
  for _, name in ipairs({ "pokemon", "items", "moves" }) do
    local src = Art._read(prefix, "data/generated/" .. name .. ".lua")
    local chunk = src and (loadstring or load)(src, "=" .. version .. "/" .. name)
    local ok, rec = false, nil
    if chunk then ok, rec = pcall(chunk) end
    if ok and type(rec) == "table" then out[name] = rec end
  end
  return out
end

local function moveIndex(src, id)
  if type(id) == "number" then return id end
  local def = src.moves and src.moves[id]
  if def and tonumber(def.index) then return tonumber(def.index) end
  return tonumber(tostring(id):match("^MOVE_(%d+)$"))
end

-- why a Game Pak Pokemon may not come, or nil when it may
function P.refusal(src, raw)
  if type(raw) ~= "table" or not raw.species then return "nothing there" end
  if raw.isEgg then return "egg" end
  for _, m in ipairs(raw.moves or {}) do
    if P.HM_MOVES[moveIndex(src, m.id) or -1] then return "hm" end
  end
  return nil
end

-- a Game Pak Pokemon in this game's own shape (Pokemon_FromGBA)
function P.fromGen3(game, version, src, raw)
  local data = game.data
  local Link = require("src.pokewalker.WalkerLink")
  local dex = Link.dexOf(version, raw.species)
  local def = dex and data.pokemon[dex]
  if not def then return nil, "unknown species" end
  local Growth = require("src.pokemon.Growth")
  local level = tonumber(raw.level)
  if not level and raw.exp then level = Growth.levelForExp(def.growthRate, raw.exp) end
  level = math.max(1, math.min(100, level or 5))
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(data, dex, level)
  mon.exp = tonumber(raw.exp) or mon.exp
  mon.evs = raw.evs or mon.evs
  mon.otId, mon.secretId = raw.otId, raw.secretId
  mon.ot = raw.gen3OtName or raw.ot
  mon.nickname = raw.nickname
  mon.happiness = tonumber(raw.happiness) or mon.happiness
  mon.contest = raw.contest or mon.contest
  mon.pokerus = raw.gen3Pokerus or raw.pokerus
  mon.markings = raw.gen3Markings
  mon.gen3Origin = version
  mon.metLevel = level
  local items, moves = byName(data.items), data.moves or {}
  local srcItems = src.items or {}
  local function itemId(key)
    if key == nil then return nil end
    local d = srcItems[key]
    local name = (d and d.name) or tostring(key):gsub("^ITEM_", ""):gsub("_", " ")
    -- Gen IV ids by the English name (Gen4EnglishRef), so a German Platinum
    -- keeps the held item; an English cache matches by its own names as before
    return require("src.pokemon.CrossGen").itemByName(data, name) or items[norm(name)]
  end
  mon.item = itemId(raw.item)
  mon.ball = itemId(raw.ball) or itemId("POKE_BALL")
  mon.moves = {}
  for _, m in ipairs(raw.moves or {}) do
    local id = moveIndex(src, m.id)
    local mdef = id and moves[id]
    if mdef then
      mon.moves[#mon.moves + 1] = { id = id, pp = tonumber(m.pp) or mdef.pp or 0, ppUps = m.ppUps }
    end
  end
  if #mon.moves == 0 then mon.moves = Pokemon.new(data, dex, level).moves end
  -- personality and IVs last: nature, ability and the stats come off them
  Pokemon.applySeed(data, mon, { personality = raw.personality, ivs = raw.ivs })
  -- the Game Pak's own answer (Gen3Save derives it from the whole 32-bit id;
  -- the port keeps the halves apart and the flag carries it)
  mon.shiny = raw.shiny or nil
  if not mon.shiny and raw.personality and mon.otId and raw.secretId then
    local Stats = require("src.pokemon.Stats")
    mon.shiny = Stats.isShinyGen3(raw.personality, mon.otId + raw.secretId * 65536) or nil
  end
  mon.hp = mon.stats and mon.stats.hp or mon.hp
  return mon
end

-- the Game Pak's key for the once-a-day rule: the game and its trainer
function P.sourceKey(version, save)
  local id = save and save.player and save.player.id or 0
  return ("%s:%s"):format(version, tostring(id))
end

-- seconds until this Game Pak may migrate again (0: now)
function P.wait(save, key)
  local at = P.store(save).migrated[key]
  if not at then return 0 end
  return math.max(0, P.ONCE_PER - (os.time() - at))
end

-- why this DS save may not migrate at all, or nil
function P.blocked(save)
  if not (save and save.pokedex and save.pokedex.national) then return "nationalDex" end
  if P.count(save) > 0 then return "parkFull" end
  return nil
end

-- migrate(game, version, slotId, picks) -> true or nil, why
--
-- `picks` are { box, index } of six Pokemon in that save's PC. The DS save
-- gets them in its transfer storage; the Game Pak loses them (backed up first).
function P.migrate(game, version, slotId, picks)
  local save = game.save
  local why = P.blocked(save)
  if why then return nil, why end
  if type(picks) ~= "table" or #picks ~= P.MONS then return nil, "needSix" end
  local SaveData = require("src.core.SaveData")
  local Ser = require("src.core.SaveSerializer")
  local path = SaveData.slotDiskPath(version, slotId)
  local f = path and io.open(path, "rb")
  if not f then return nil, "noSave" end
  local bytes = f:read("*a"); f:close()
  local okD, gba = pcall(Ser.decode, bytes)
  if not (okD and type(gba) == "table") then return nil, "noSave" end
  local okO, open = pcall(SaveData.slotOpenElsewhere, version, slotId)
  if okO and open then return nil, "open" end
  local key = P.sourceKey(version, gba)
  if P.wait(save, key) > 0 then return nil, "today" end
  local src = P.sourceData(version)
  local boxes = gba.boxes
  if type(boxes) ~= "table" and type(gba.box) == "table" then boxes = gba.box.boxes or { gba.box } end
  local mons, fromWalker = {}, {}
  for i, pick in ipairs(picks) do
    local mon, err
    if pick.walker then
      -- the Monster Walker's catches fill places too (src/pokemon/CrossGen.lua)
      mon, err = require("src.pokemon.CrossGen").fromWalker(game, pick.entry)
      fromWalker[#fromWalker + 1] = pick.walker
    else
      local box = boxes and boxes[pick.box]
      local list = box and (box.mons or box)
      local raw = list and list[pick.index]
      if P.refusal(src, raw) then return nil, P.refusal(src, raw) end
      mon, err = P.fromGen3(game, version, src, raw)
    end
    if not mon then return nil, err end
    mons[i] = mon
  end
  -- the Game Pak first, so a failed write leaves both games as they were
  if love and love.filesystem then
    local dir = ("pal_park_backups/%s"):format(version)
    love.filesystem.createDirectory(dir)
    love.filesystem.write(("%s/%s_%s.lua"):format(dir, slotId, os.date("%Y%m%d_%H%M%S")), bytes)
  end
  for _, pick in ipairs(picks) do
    if not pick.walker then
      local list = boxes[pick.box].mons or boxes[pick.box]
      list[pick.index] = nil
    end
  end
  local ok, err = SaveData.writeSlot(version, slotId, gba)
  if not ok then return nil, err or "write" end
  require("src.pokemon.CrossGen").takeWalker(fromWalker)
  local st = P.store(save)
  for i = 1, P.MONS do st.transfer[i] = mons[i] end
  st.migrated[key] = os.time()
  return true
end

-- the Gen III saves on disk: { { version, slot, name, label } }
function P.sources()
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")
  local out = {}
  for _, version in ipairs(P.GEN3_VERSIONS) do
    local okI, info = pcall(GameVersion.info, version)
    if okI and info then
      local okL, slots = pcall(SaveData.listSlots, version)
      for _, s in ipairs(okL and slots or {}) do
        if s.exists then
          out[#out + 1] = { version = version, slot = s.id, name = s.name,
                            label = s.label, title = info.title or info.name or version }
        end
      end
    end
  end
  return out
end

return P
