-- PLATINUM'S BATTLE LINES IN THE CARTRIDGE'S OWN LANGUAGE.
--
-- The Gen 4 battle prints the engine's English ("Wild X\nappeared!", "Enemy X
-- used Y!").  On an English cartridge that is the game's own wording; on a
-- German one it is English in the middle of a German game.  The cartridge's
-- lines are in text bank 368 (the battle) and bank 0 (a line per move:
-- 3 * move + side), three variants per line like Black / White's: the
-- player's Pokemon (+0), the wild one (+1) and the foe's (+2).
--
-- Like src/battle/Gen5BattleText.lua this is applied where a battle message
-- starts (BattleState:startMessage), and only on a non-English cartridge
-- (`data.gen4_language`), so an English cache prints exactly what it did.  A
-- line no pattern knows is left as the engine wrote it.
--
-- The indices were read off an imported US cache by the line they start with
-- (grep TEXT_B0368_<n>); the placeholders ({STRVAR_1 <type> <slot> 0}) are
-- filled from the arguments by type: 1 a Pokemon name, 3 a trainer, 6 a move,
-- 13 a stat, 50/52/54 a number.

local T = {}

T.BANK = 368
T.BANK_MOVE_USED = 0

-- the engine's stat labels -> the summary's stat-name entries (bank 201)
T.STAT_TEXT = { ["ATTACK"] = 54, ["DEFENSE"] = 56, ["SP. ATK"] = 58, ["SP. DEF"] = 60, ["SPEED"] = 62 }

local function key(bank, index) return ("TEXT_B%04d_%05d"):format(bank, index) end

local function line(data, bank, index)
  local s = data and data.text and data.text[key(bank, index)]
  return type(s) == "string" and s ~= "" and s or nil
end

-- fill a cartridge line: vals[type] = { slot0, slot1, ... }
local function fill(raw, vals)
  local out = raw:gsub("{WAIT %d+}", ""):gsub("{STRVAR_1 (%d+) (%d+) %d+}", function(kind, slot)
    local list = vals[tonumber(kind)]
    local v = list and list[tonumber(slot) + 1]
    return v ~= nil and tostring(v) or ""
  end)
  -- the ROM's trailing wait marker is the box's own concern
  out = out:gsub("[\011]+$", "")
  return out
end

-- which of the three variants a printed name belongs to
local function side(battle, enemyPrefix)
  if not enemyPrefix or enemyPrefix == "" then return 0 end
  return battle.trainer and 2 or 1
end

local function moveIdByName(battle, name)
  local map = battle._gen4MoveIdByName
  if not map then
    map = {}
    for id, def in pairs((battle.data and battle.data.moves) or {}) do
      if type(id) == "number" and type(def) == "table" and def.name and map[def.name] == nil then map[def.name] = id end
    end
    battle._gen4MoveIdByName = map
  end
  return map[name]
end

-- the three-variant line (index = base + side) with the Pokemon name in slot 0
local function three(base, extra)
  return function(battle, prefix, name, ...)
    local raw = line(battle.data, T.BANK, base + side(battle, prefix))
    if not raw then return nil end
    local vals = { [1] = { name } }
    if extra then extra(vals, ...) end
    return fill(raw, vals)
  end
end

-- patterns: { lua pattern over the engine's text, handler(battle, captures...) }
T.PATTERNS = {
  { "^(Enemy )(.-)\nused (.-)!$", function(battle, prefix, name, move)
      local id = moveIdByName(battle, move)
      local raw = id and line(battle.data, T.BANK_MOVE_USED, 3 * id + side(battle, prefix))
      return raw and fill(raw, { [1] = { name } }) end },
  { "^(.-)\nused (.-)!$", function(battle, name, move)
      local id = moveIdByName(battle, move)
      local raw = id and line(battle.data, T.BANK_MOVE_USED, 3 * id)
      return raw and fill(raw, { [1] = { name } }) end },
  { "^Wild (.-)\nappeared!$", function(battle, name)
      local raw = line(battle.data, T.BANK, 1246)
      return raw and fill(raw, { [1] = { name } }) end },
  { "^Go! (.-)!$", function(battle, name)
      local raw = line(battle.data, T.BANK, 979)
      return raw and fill(raw, { [1] = { name } }) end },
  { "^(Enemy )(.-)\nfainted!$", three(30) },
  { "^(.-)\nfainted!$", function(battle, name) return three(30)(battle, "", name) end },
  { "^It's super\neffective!$", function(battle) return line(battle.data, T.BANK, 780) and fill(line(battle.data, T.BANK, 780), {}) end },
  { "^It's not very\neffective%.%.%.$", function(battle) return line(battle.data, T.BANK, 779) and fill(line(battle.data, T.BANK, 779), {}) end },
  { "^Critical hit!$", function(battle) return line(battle.data, T.BANK, 774) and fill(line(battle.data, T.BANK, 774), {}) end },
  { "^One%-hit KO!$", function(battle) return line(battle.data, T.BANK, 775) and fill(line(battle.data, T.BANK, 775), {}) end },
  { "^(Enemy )(.-)'s\nattack missed!$", three(12) },
  { "^(.-)'s\nattack missed!$", function(battle, name) return three(12)(battle, "", name) end },
  { "^It doesn't affect\n(Enemy )(.-)%.%.%.$", three(27) },
  { "^It doesn't affect\n(.-)%.%.%.$", function(battle, name) return three(27)(battle, "", name) end },
  { "^(.-) gained\n(%d+) EXP%. Points!$", function(battle, name, n)
      local raw = line(battle.data, T.BANK, 1)
      return raw and fill(raw, { [1] = { name }, [54] = { nil, n } }) end },
  { "^(.-) grew\nto level (%d+)!$", function(battle, name, n)
      local raw = line(battle.data, T.BANK, 3)
      return raw and fill(raw, { [1] = { name }, [52] = { nil, n } }) end },
  { "^Gotcha!\n(.-) was caught!$", function(battle, name)
      local raw = line(battle.data, T.BANK, 867)
      return raw and fill(raw, { [1] = { name } }) end },
  { "^Got away safely!$", function(battle) return line(battle.data, T.BANK, 781) and fill(line(battle.data, T.BANK, 781), {}) end },
  { "^Can't escape!$", function(battle) return line(battle.data, T.BANK, 42) and fill(line(battle.data, T.BANK, 42), {}) end },
  { "^(.-) sent\nout (.-)!$", function(battle, who, mon)
      local raw = line(battle.data, T.BANK, 974)
      return raw and fill(raw, { [3] = { who }, [1] = { nil, mon } }) end },
  -- "Bug Catcher Jack wants to fight!": the class and the name are the
  -- trainer record's, which the cartridge prints from two slots
  { "^(.-) wants\nto fight!$", function(battle)
      local t = battle.trainer
      local raw = t and line(battle.data, T.BANK, 969)
      return raw and fill(raw, { [14] = { t.className }, [3] = { nil, t.name } }) end },
  -- "(Enemy )NAME's\nSTAT rose!" / "fell!"
  { "^(Enemy )(.-)'s\n(.-) (rose)!$", nil },
}

-- a stat change names the stat in the cartridge's language
local function statLine(base)
  return function(battle, prefix, name, stat)
    local at = T.STAT_TEXT[stat]
    local label = at and line(battle.data, 201, at)
    if not label then return nil end
    return three(base, function(vals) vals[13] = { label } end)(battle, prefix, name)
  end
end
T.PATTERNS[#T.PATTERNS] = nil
T.PATTERNS[#T.PATTERNS + 1] = { "^(Enemy )(.-)'s\n(.-) rose!$", statLine(750) }
T.PATTERNS[#T.PATTERNS + 1] = { "^(.-)'s\n(.-) rose!$", function(battle, name, stat) return statLine(750)(battle, "", name, stat) end }
T.PATTERNS[#T.PATTERNS + 1] = { "^(Enemy )(.-)'s\n(.-) fell!$", statLine(762) }
T.PATTERNS[#T.PATTERNS + 1] = { "^(.-)'s\n(.-) fell!$", function(battle, name, stat) return statLine(762)(battle, "", name, stat) end }

-- the engine's line in, the cartridge's out (or the engine's, unchanged)
function T.translate(battle, text)
  if type(text) ~= "string" or text == "" then return text end
  local data = battle and battle.data
  if not (data and data.gen4_language) then return text end
  for _, row in ipairs(T.PATTERNS) do
    local fn = row[2]
    if fn then
      local caps = { text:match(row[1]) }
      if caps[1] ~= nil then
        local ok, out = pcall(fn, battle, caps[1], caps[2], caps[3])
        if ok and type(out) == "string" and out ~= "" then return out end
      end
    end
  end
  return text
end

return T
