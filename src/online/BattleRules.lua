-- Link battle rules (docs/online-design.md 2.5, WS5).
--
-- One plain table, dealt by the host with the party message and read by both
-- machines, so a lockstep battle is built from identical teams:
--
--   {
--     format  = "single" | "double",
--     level   = nil | { mode = "flat" | "force", value = 50 },
--               flat:  scale DOWN only -- a Pokemon above the value fights
--                      at it, one below keeps its own level (the Gen 3-5
--                      Colosseum / B/W "Flat" rule)
--               force: everyone at exactly the value (the 0.7.x ANY/50/100
--                      picker, Gen 1/2 behaviour, kept for old peers)
--     teamSize = nil | n     the first n able Pokemon of each party fight
--     speciesClause = bool   no two Pokemon of one species on a team
--     itemClause    = bool   no two Pokemon holding the same item
--     sleepClause   = bool   a side's opponent may keep only one of its
--                            Pokemon asleep at a time (enforced in battle)
--     heal          = bool   everyone starts at full HP and PP, no status
--   }
--
-- The clauses are checked on the PACKED party (MonCodec / Protocol packets),
-- so both machines reach the same verdict without unpacking anything.
-- Which presets a cartridge's link battle offered lives in PRESETS; the
-- clauses are port toggles on Gen 1/2, where the cable had none.

local BattleRules = {}

-- what each generation's own link battle let the players choose
BattleRules.PRESETS = {
  -- Gen 1 / 2 Cable Club: no rules at all, the party as it stands.  The
  -- 0.7.x level picker (ANY / 50 / 100, forced) stays as a port extension.
  [1] = {
    { id = "none", label = "NO RULES" },
    { id = "force50", label = "LEVEL 50", level = { mode = "force", value = 50 } },
    { id = "force100", label = "LEVEL 100", level = { mode = "force", value = 100 } },
  },
  -- Gen 3 Cable Club Colosseum: SINGLE or DOUBLE battle, the whole party,
  -- no level adjustment.  Clauses are offered as port toggles.
  [3] = {
    { id = "single", label = "SINGLE BATTLE", format = "single" },
    { id = "double", label = "DOUBLE BATTLE", format = "double" },
  },
  -- Gen 4 Colosseum (Pt / HGSS): single, double; "no restrictions" or a
  -- level-50 scale-down with the cup's clauses
  [4] = {
    { id = "single", label = "SINGLE BATTLE", format = "single" },
    { id = "double", label = "DOUBLE BATTLE", format = "double" },
    { id = "single50", label = "SINGLE LV.50", format = "single",
      level = { mode = "flat", value = 50 }, speciesClause = true, itemClause = true },
    { id = "double50", label = "DOUBLE LV.50", format = "double",
      level = { mode = "flat", value = 50 }, speciesClause = true, itemClause = true },
  },
  -- Gen 5 link / Union Room: Normal or Flat (Lv.50 scale-down), singles and
  -- doubles (triples and rotation are not in this engine)
  [5] = {
    { id = "single", label = "SINGLE NORMAL", format = "single" },
    { id = "double", label = "DOUBLE NORMAL", format = "double" },
    { id = "singleFlat", label = "SINGLE FLAT", format = "single",
      level = { mode = "flat", value = 50 }, speciesClause = true, itemClause = true },
    { id = "doubleFlat", label = "DOUBLE FLAT", format = "double",
      level = { mode = "flat", value = 50 }, speciesClause = true, itemClause = true },
  },
}
BattleRules.PRESETS[2] = BattleRules.PRESETS[1]

local function genOf(gen)
  gen = tonumber(gen) or 1
  if gen < 1 then gen = 1 elseif gen > 5 then gen = 5 end
  return math.floor(gen)
end

-- the default rules for a generation (the cartridge's plain link battle)
function BattleRules.defaults(gen)
  gen = genOf(gen)
  return {
    format = "single",
    heal = gen >= 3,
    speciesClause = false, itemClause = false, sleepClause = false,
  }
end

-- a preset by id, merged over the defaults
function BattleRules.preset(gen, id)
  local out = BattleRules.defaults(gen)
  for _, p in ipairs(BattleRules.PRESETS[genOf(gen)] or {}) do
    if p.id == id then
      for k, v in pairs(p) do
        if k ~= "id" and k ~= "label" then out[k] = v end
      end
      out.preset = id
      return out
    end
  end
  return out
end

-- The rules as they cross the wire (and as they are read back): only the
-- known keys, every value checked, so a peer cannot smuggle anything in.
function BattleRules.sanitize(rules, gen)
  local out = BattleRules.defaults(gen)
  if type(rules) ~= "table" then return out end
  if rules.format == "double" or rules.format == "multi" then out.format = rules.format end
  local lv = rules.level
  if type(lv) == "table" and (lv.mode == "flat" or lv.mode == "force") then
    local v = tonumber(lv.value)
    if v then
      out.level = { mode = lv.mode, value = math.max(1, math.min(100, math.floor(v))) }
    end
  end
  local n = tonumber(rules.teamSize)
  if n then out.teamSize = math.max(1, math.min(6, math.floor(n))) end
  for _, k in ipairs({ "speciesClause", "itemClause", "sleepClause", "heal" }) do
    if rules[k] ~= nil then out[k] = rules[k] == true end
  end
  if type(rules.preset) == "string" then out.preset = rules.preset:sub(1, 24) end
  return out
end

-- The 0.7.x level picker on the wire (opts.forceLevel, a number or nil),
-- read into rules: a forced level for everyone, as before.
function BattleRules.fromForceLevel(forceLevel, gen)
  local out = BattleRules.defaults(gen)
  local v = tonumber(forceLevel)
  if v then out.level = { mode = "force", value = v } end
  return BattleRules.sanitize(out, gen)
end

-- The level this packed Pokemon fights at under the rules, as the
-- forceLevel unpack option: nil keeps its own level.
function BattleRules.levelFor(rules, packed)
  local lv = type(rules) == "table" and rules.level
  if type(lv) ~= "table" then return nil end
  local own = tonumber(type(packed) == "table" and packed.level) or 1
  if lv.mode == "force" then return lv.value end
  if lv.mode == "flat" and own > lv.value then return lv.value end
  return nil
end

local function isEgg(p)
  return type(p) == "table" and (p.isEgg == true or p.isEgg == 1 or p.egg == true)
end

-- The team that fights: eggs dropped, then the first `teamSize`.  A fainted
-- Pokemon still goes (`heal` restores it; without it, it sits on the bench).
function BattleRules.team(rules, packedParty)
  local out = {}
  local limit = type(rules) == "table" and tonumber(rules.teamSize) or nil
  for _, p in ipairs(packedParty or {}) do
    if type(p) == "table" and not isEgg(p) then
      out[#out + 1] = p
      if limit and #out >= limit then break end
    end
  end
  return out
end

-- The clauses, checked over a team.  Returns true, or false plus a short
-- reason naming the first offence (shown on both screens).
function BattleRules.check(rules, team, data)
  if type(rules) ~= "table" then return true end
  local function nameOf(p)
    local def = data and data.pokemon and data.pokemon[p.species]
    return (p.nickname and p.nickname ~= "" and p.nickname)
      or (def and def.name) or tostring(p.species)
  end
  if rules.speciesClause then
    local seen = {}
    for _, p in ipairs(team) do
      local key = tostring(p.species)
      if seen[key] then
        return false, ("Two %s on one team\n(Species Clause)."):format(nameOf(p))
      end
      seen[key] = true
    end
  end
  if rules.itemClause then
    local seen = {}
    for _, p in ipairs(team) do
      local item = p.item
      if item ~= nil and item ~= 0 and item ~= "" and item ~= "NONE" then
        local key = tostring(item)
        if seen[key] then
          return false, ("Two POKéMON hold the\nsame item (Item Clause).")
        end
        seen[key] = true
      end
    end
  end
  if rules.format == "double" and #team < 2 then
    return false, "A DOUBLE BATTLE needs\ntwo POKéMON."
  end
  if #team == 0 then return false, "No POKéMON can battle." end
  return true
end

-- ------------------------------------------------------------ multi battles
--
-- THE 4-PLAYER MULTI BATTLE (src/online/MultiBattle.lua): two players a
-- side, one slot each, every player bringing their own team.
--   Gen 3  Cable Club / wireless multi: three Pokemon each, chosen in order
--          (ChooseHalfPartyForBattle, special 42), no level adjustment
--   Gen 4  Colosseum MULTI: three each; the Lv.50 rule set scales down
--   Gen 5  link multi: three each (Normal / Flat); the Battle Subway's
--          Wireless Multi Train is two each at level 50 (ov21 0x021CA270:
--          MEMBERS[3] = 2, the Subway's "level down")
-- format = "multi" runs as the engine's double; `teamSize` is per player.
BattleRules.MULTI_PRESETS = {
  [3] = {
    { id = "multi", label = "MULTI BATTLE", format = "multi", teamSize = 3 },
  },
  [4] = {
    { id = "multi", label = "MULTI BATTLE", format = "multi", teamSize = 3 },
    { id = "multi50", label = "MULTI LV.50", format = "multi", teamSize = 3,
      level = { mode = "flat", value = 50 }, speciesClause = true, itemClause = true },
  },
  [5] = {
    { id = "multi", label = "MULTI NORMAL", format = "multi", teamSize = 3 },
    { id = "multiFlat", label = "MULTI FLAT", format = "multi", teamSize = 3,
      level = { mode = "flat", value = 50 }, speciesClause = true, itemClause = true },
    { id = "subway", label = "SUBWAY MULTI", format = "multi", teamSize = 2,
      level = { mode = "flat", value = 50 }, speciesClause = true, itemClause = true },
  },
}

function BattleRules.isMulti(rules)
  return type(rules) == "table" and rules.format == "multi"
end

-- the multi rules for a generation (preset `id`, else the plain multi)
function BattleRules.multi(gen, id)
  gen = genOf(gen)
  local list = BattleRules.MULTI_PRESETS[math.max(3, gen)] or BattleRules.MULTI_PRESETS[3]
  local pick = list[1]
  for _, p in ipairs(list) do if p.id == id then pick = p end end
  local out = BattleRules.defaults(gen)
  for k, v in pairs(pick) do
    if k ~= "id" and k ~= "label" then out[k] = v end
  end
  out.preset = pick.id
  return BattleRules.sanitize(out, gen)
end

-- the team a multi player chooses: how many (most) and the fewest allowed
function BattleRules.multiCount(rules)
  local n = type(rules) == "table" and tonumber(rules.teamSize) or 3
  return n or 3, 1
end

-- A one-line description of the rules, for the LINK screens.
function BattleRules.describe(rules)
  if type(rules) ~= "table" then return "NO RULES" end
  local parts = { rules.format == "double" and "DOUBLE" or (rules.format == "multi" and "MULTI") or "SINGLE" }
  local lv = rules.level
  if type(lv) == "table" then
    parts[#parts + 1] = (lv.mode == "flat" and "LV.%d FLAT" or "LV.%d"):format(lv.value)
  end
  if rules.speciesClause then parts[#parts + 1] = "SPECIES" end
  if rules.itemClause then parts[#parts + 1] = "ITEM" end
  if rules.sleepClause then parts[#parts + 1] = "SLEEP" end
  return table.concat(parts, " ")
end

-- ------------------------------------------------------------ sleep clause

-- The moves whose whole purpose is to put the target to sleep (Gen 3 names,
-- Gen 4/5 move ids).  A side may have only one of its Pokemon asleep by the
-- opponent's hand; while one is, these fail.
BattleRules.SLEEP_MOVES = {
  SPORE = true, HYPNOSIS = true, SLEEP_POWDER = true, SING = true,
  LOVELY_KISS = true, GRASSWHISTLE = true, GRASS_WHISTLE = true, YAWN = true,
  DARK_VOID = true,
  [147] = true, [95] = true, [79] = true, [47] = true, [142] = true,
  [320] = true, [281] = true, [464] = true,
}

function BattleRules.isSleepMove(data, id)
  if id == nil then return false end
  if BattleRules.SLEEP_MOVES[id] then return true end
  local def = data and data.moves and data.moves[id]
  local name = def and type(def.name) == "string" and def.name:upper():gsub("[%s%-]", "_")
  return name and BattleRules.SLEEP_MOVES[name] == true or false
end

return BattleRules
