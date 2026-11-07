-- WHERE A DS GAME SENDS YOU WHEN YOU WHITE OUT, AND WHAT IT SAYS ON THE WAY.
--
-- Platinum, HeartGold / SoulSilver and Black / White all return a blacked-out
-- player to the LAST POKEMON CENTER THEY WALKED INTO, standing at the counter
-- in front of the nurse and facing her -- or to their home before they have
-- seen one. Until this module nothing in the port wrote that record for a DS
-- game: `OverworldState:healPoint` answered `save.lastHeal`, which only the
-- Game Boy and GBA paths write, so every Gen 4 / Gen 5 whiteout fell through
-- to the new game's `boot.lastHeal` -- the player's house -- however many
-- Centers they had healed at ("I lost at the first gym and I ended back in
-- the start even though I healed at the Poke Center").
--
-- THE RECORD (noteEntry, every map load):
--
--   Gen 4  the field's spawn table (`field.healLocations`, Gen4Field /
--          Gen4HgssField: Platinum's sHealLocations, HGSS's sSpawnMaps). A
--          row's BLACKOUT half names the Center's ground floor and the cell
--          at its counter; entering that map makes the row the blackout spawn
--          (FieldMapChange_UpdateGameData's warp-id update on map load). HGSS
--          rows carry an isBlackoutSpawn bit; a cache imported before it was
--          kept falls back to "the blackout map is an interior of its own"
--          (the rows whose blackout half is an outdoor town are fly-only).
--   Gen 5  Black / White's Centers are the zones whose nurse runs the shared
--          nurse script (band 2100); the spawn is two cells in front of her,
--          across the counter -- the same cell BW's own whiteout script
--          measures back from (`getplayermappos; subvar y, 2`).
--
-- THE SEQUENCE (begin, from warpToHealPoint on a whiteout):
--
--   1. the black screen with the cartridge's own line -- "<PLAYER> scurried to
--      a Pokemon Center, protecting ..." or "... scurried back home ..."
--      (HGSS bank 203 #3/#4, Platinum 373 #3/#4, BW system bank 37 #2/#3)
--   2. the warp, landing facing UP at the counter
--   3. the ROM's own whiteout script from the common-script band: the nurse's
--      "First, let's restore your Pokemon to full health." (HGSS std 2013,
--      Platinum 2021, BW 854's second entry) or Mom's at home (Gen 4).
--
-- The money is not taken here: the DS games take it IN BATTLE
-- (BtlCmd_PayPrizeMoney), see `M.lossLines`.

local M = {}

local GameVersion = require("src.core.GameVersion")

-- --------------------------------------------------------------- the text --

local function textOf(data, key)
  local t = data and data.text
  local s = t and t[key]
  return type(s) == "string" and s or nil
end

local function gen4Key(bank, i) return ("TEXT_B%04d_%05d"):format(bank, i) end
local function gen5SysKey(bank, i) return ("TEXT_G5S_%04d_%05d"):format(bank, i) end

-- a cartridge line with the player's name put in and the trailing waits off.
-- The values go in through the shared Gen 4 buffer / markup, the way the
-- cartridge's template does it: slot 0 the player (BufferPlayerName), slot 1
-- the money (BufferMoney) -- Gen 5's {VARn} / {CMD 0204 n} read the same
-- slots. Black / White's "scurried" line names the player from slot 1, so
-- with no amount the name fills that slot too.
local function finish(s, name, amount)
  if not s then return nil end
  local ctx = {}
  require("src.import.Gen4Text").buffer(ctx, name or "",
    amount ~= nil and tostring(amount) or (name or ""))
  local ok, Commands = pcall(require, "src.script.Commands")
  if ok and Commands and Commands.gen4Markup then
    local okM, plain = pcall(Commands.gen4Markup, s, ctx)
    if okM and type(plain) == "string" then s = plain end
  end
  s = s:gsub("[\v\f\n ]+$", "")
  return s
end

-- The battle's loss lines, bank by bank: Platinum's battle bank is 368,
-- HeartGold / SoulSilver's is 197 (the same entries, renumbered banks), and
-- Black / White's is system bank 15. The bank is CHECKED, not assumed: a
-- bank whose "blacked out" entry does not say so is not the one.
--   -> { out = "...", panic = "...", paid = "...", dots = "...", blackedOut = "..." }
function M.lossBank(data)
  for _, bank in ipairs({ 368, 197 }) do
    local s = textOf(data, gen4Key(bank, 37))
    if s and s:find("blacked out") then
      return { out = gen4Key(bank, 36), panic = gen4Key(bank, 34), paid = gen4Key(bank, 35),
               dots = gen4Key(bank, 38), blackedOut = gen4Key(bank, 37) }
    end
  end
  local s = textOf(data, gen5SysKey(15, 57))
  if s and s:find("blacked out") then
    return { out = gen5SysKey(15, 54), panic = gen5SysKey(15, 55), paid = gen5SysKey(15, 56),
             blackedOut = gen5SysKey(15, 57) }
  end
  return nil
end

-- The lines a lost battle prints, in order, with `penalty` already worked
-- out (OverworldState.gen4MoneyPenalty -- Gen 5 uses the same table). nil
-- when the cache carries no loss bank at all.
function M.lossLines(data, name, penalty, trainer)
  local bank = M.lossBank(data)
  if not bank then return nil end
  local out = {}
  local function add(key, amount)
    local s = finish(key and textOf(data, key), name, amount)
    if s and s ~= "" then out[#out + 1] = s end
  end
  add(bank.out)
  if (penalty or 0) > 0 then add(trainer and bank.paid or bank.panic, penalty) end
  add(bank.dots)
  add(bank.blackedOut)
  return out
end

-- "<PLAYER> scurried to a Pokemon Center ..." / "... scurried back home ..."
function M.scurryLine(data, name, home)
  local s = textOf(data, gen4Key(203, home and 4 or 3))   -- HGSS
  if not (s and s:find("scurried")) then s = textOf(data, gen4Key(373, home and 4 or 3)) end -- Platinum
  if not (s and s:find("scurried")) then s = textOf(data, gen5SysKey(37, home and 3 or 2)) end -- BW
  if not (s and s:find("scurried")) then
    s = home and "{PLAYER} scurried back home, protecting the exhausted and fainted Pokémon from further harm..."
            or "{PLAYER} scurried to a Pokémon Center, protecting the exhausted and fainted Pokémon from further harm..."
  end
  return finish(s, name)
end

-- ------------------------------------------------------------- the record --

local function nurseOf(def)
  for _, o in ipairs((def and (def.objects or def.npcs)) or {}) do
    if tonumber(o.script) == 2100 and o.x and o.y then return o end
  end
  return nil
end

-- The blackout spawn a map IS, or nil: { map, x, y, facing, home }.
function M.spawnFor(data, mapId, def)
  if not (data and mapId) then return nil end
  if GameVersion.isGen5() then
    -- READ, ov20 0x02185862 -> ov10 0x02159FE0: a map load into a zone that
    -- is some warp row's whiteout zone (mode bit 0 set) makes that row the
    -- whiteout point -- the Centers, and the house's ground floor (Z390, the
    -- game's "home"); src/script/Gen5StorySwaps.lua WARP_ROWS
    local Swaps = require("src.script.Gen5StorySwaps")
    for id, row in ipairs(Swaps.WARP_ROWS) do
      if id ~= 14 and id ~= 17 and ("Z%03d"):format(row[1]) == mapId then
        local h = Swaps.healFor(id)
        return { map = h.map, x = h.x, y = h.y, facing = h.facing, home = h.home }
      end
    end
    local nurse = nurseOf(def or (data.maps and data.maps[mapId]))
    if nurse then return { map = mapId, x = nurse.x, y = nurse.y + 2, facing = "up" } end
    return nil
  end
  local rows = data.field and data.field.healLocations
  for i, row in ipairs(rows or {}) do
    local b = row.blackOut
    if b and b.map == mapId and b.x and b.y then
      local ok
      if row.isBlackoutSpawn ~= nil then ok = row.isBlackoutSpawn
      else ok = not (row.fly and row.fly.map == b.map) end
      if ok then
        return { map = mapId, x = b.x, y = b.y, facing = "up", home = (i == 1) or nil, row = row.index }
      end
    end
  end
  return nil
end

-- Called on every map load of a DS game: entering a Center (or, on Gen 4, the
-- house's ground floor) makes it the blackout spawn.
function M.noteEntry(ow, game)
  if not (game and game.save and game.data and ow and ow.map) then return end
  if not GameVersion.isNds() then return end
  local spawn = M.spawnFor(game.data, ow.map.id, ow.map.def)
  if not spawn then return end
  local last = game.save.lastHeal
  if last and last.map == spawn.map and last.x == spawn.x and last.y == spawn.y then return end
  game.save.lastHeal = { map = spawn.map, x = spawn.x, y = spawn.y, facing = spawn.facing,
                         home = spawn.home }
end

-- Is this heal point the player's home (the "scurried back home" line, Mom)?
function M.isHome(data, heal)
  if not heal then return false end
  if heal.home ~= nil then return heal.home and true or false end
  local boot = data and data.field and data.field.boot
  local h = boot and boot.lastHeal
  return h ~= nil and h.map == heal.map
end

-- ------------------------------------------------- the ROM's own script --

-- The common-script band's whiteout entries, found by what they print: the
-- nurse's "First, let's restore your Pokemon to full health." picks the
-- Center's script, and (Gen 4) the entry printing the line three before it,
-- Mom's "Welcome home", with a heal in it, is the house's.
function M.whiteoutLabel(data, home)
  local pool = data and data.map_scripts
  local band = pool and pool.bands and pool.bands.common_scripts
  local scripts = pool and pool.scripts
  if not (band and band.entries and band.textBank and scripts) then return nil end
  local bank = band.textBank
  local nurseIndex
  for i = 0, 400 do
    local s = textOf(data, gen4Key(bank, i))
    if s and s:find("^First, let.-s restore your Pok") then nurseIndex = i break end
  end
  if not nurseIndex then return nil end
  local function has(label, index, needHeal)
    local s = scripts[label]
    local found, healed = false, false
    for _, ins in ipairs((s and s.instructions) or {}) do
      if ins.name == "message" and ins.args and ins.args[1] == index then found = true end
      if ins.name == "healparty" then healed = true end
    end
    return found and (healed or not needHeal)
  end
  for _, label in ipairs(band.entries) do
    if home then
      local mom = textOf(data, gen4Key(bank, nurseIndex - 3))
      if mom and mom:find("^Mom") and has(label, nurseIndex - 3, true) then return label end
    elseif has(label, nurseIndex) then
      return label
    end
  end
  return nil
end

-- Black / White's nurse script finds the nurse itself: `getplayermappos
-- 8020, 8021; subvar 8021, 2; 0x070 ...` asks for the person two cells
-- above the player and answers 0x8022 = 1 (found) and 0x8011 = her id, and
-- only then prints her lines and bows her (applymovement 0x8011). 0x070's
-- operands are not in a cache, so its row is answered here from the map:
-- the person standing there.
local function bwNurseRows(rows, def, spawn)
  local nurse
  for _, o in ipairs((def and (def.objects or def.npcs)) or {}) do
    if spawn and o.x == spawn.x and o.y == spawn.y - 2 then nurse = o end
  end
  nurse = nurse or nurseOf(def)
  if not nurse then return rows end
  local out = {}
  for _, row in ipairs(rows) do
    if row[1] == "g4_unimplemented" and row[2] == "bw_070" then
      out[#out + 1] = { "g4_set_var", 0x8022, 1 }
      out[#out + 1] = { "g4_set_var", 0x8011, tonumber(nurse.localId) or 0 }
    else
      out[#out + 1] = row
    end
  end
  return out
end

function M.whiteoutRows(data, home, def, spawn)
  local label = M.whiteoutLabel(data, home)
  if not label then return nil end
  local ok, rows = pcall(function() return require("src.script.Gen4ScriptVM").compile(data, label) end)
  if not (ok and rows) then return nil end
  if GameVersion.isGen5() then rows = bwNurseRows(rows, def, spawn) end
  return rows
end

-- ------------------------------------------------------------ the sequence --

-- A plain black screen under the "scurried" line. It goes transparent the
-- moment the overworld is on another map (the warp under it has landed), so
-- the warp's own fade-in reveals the Center.
local Black = {}
Black.__index = Black
function Black.new(ow, fromMap)
  return setmetatable({ ow = ow, fromMap = fromMap, isOpaque = true, name = "Gen4BlackoutScreen" }, Black)
end
function Black:animate()
  local ow = self.ow
  if self.isOpaque and ow and ow.map and ow.map.id ~= self.fromMap then
    self.isOpaque, self.clear = false, true
  end
end
function Black:update() self:animate() end
function Black:draw()
  if self.clear then return end
  local g = love.graphics
  g.push("all")
  g.origin()
  local c = g.getCanvas()
  local w, h
  if c and c.getDimensions then w, h = c:getDimensions() else w, h = g.getDimensions() end
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, w, h)
  g.pop()
end

local function remove(stack, state)
  for i = #stack.states, 1, -1 do
    if stack.states[i] == state then table.remove(stack.states, i) return true end
  end
  return false
end

-- warpToHealPoint's whiteout, on a DS game: the black screen and its line
-- first, then the warp itself (`ow:warpToHealPoint` again, marked shown, with
-- the counter's facing), then the ROM's whiteout script. Returns true when it
-- has taken over; false leaves warpToHealPoint to do what it always did.
function M.begin(ow, game, opts, onDone)
  if not (GameVersion.isNds() and game and game.stack and game.data and ow) then return false end
  local heal = ow:healPoint(true)
  if not heal then return false end
  local home = M.isHome(game.data, heal)
  local name = game.save and game.save.player and game.save.player.name or ""
  local line = M.scurryLine(game.data, name, home)
  local black = Black.new(ow, ow.map and ow.map.id)
  game.stack:push(black)
  local TextBox = require("src.render.TextBox")
  local function arrive()
    -- the warp has landed and faded in: take the black screen away and let
    -- the Center's (or Mom's) own script run
    remove(game.stack, black)
    local rows = M.whiteoutRows(game.data, home, ow.map and ow.map.def, heal)
    if rows and ow.queueScript then
      ow:queueScript(rows, { mapId = ow.map and ow.map.id, whiteout = true })
    end
    if onDone then onDone() end
  end
  local function warp()
    local nextOpts = {}
    for k, v in pairs(opts or {}) do nextOpts[k] = v end
    nextOpts.gen4Shown = true
    nextOpts.facing = heal.facing or "up"
    -- a cache whose spawn did not say: the counter is above the spawn cell
    ow:warpToHealPoint(arrive, nextOpts)
  end
  game.stack:push(TextBox.new(game, line, warp))
  return true
end

return M
