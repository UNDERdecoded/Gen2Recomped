-- The opt-in content format is separate from the legacy/native schemas.
-- These are definition records, not saved Pokemon or callback payloads.
local Schemas = require("src.mods.Schemas")
local f = Schemas.f
local id = f.str
local ids = f.list(id)
local level = f.int(1, 100)
local stats = f.rec {
  hp = f.int(1, 255), attack = f.int(1, 255), defense = f.int(1, 255),
  speed = f.int(1, 255), special = f.int(1, 255),
  specialAttack = f.opt(f.int(1, 255)), specialDefense = f.opt(f.int(1, 255)),
}
local evolution = f.rec {
  method = id, species = id, level = f.opt(level), item = f.opt(id),
  time = f.opt(f.enum { "ANYTIME", "MORNDAY", "NITE" }),
  comparison = f.opt(f.enum { "ATK_GT_DEF", "ATK_LT_DEF", "ATK_EQ_DEF" }),
}
local slot = f.rec {
  species = id, level = f.opt(level), minLevel = f.opt(level), maxLevel = f.opt(level),
  chance = f.opt(f.numRange(0, 100)),
}
local area = f.rec { rate = f.numRange(0, 256), slots = f.list(slot),
  times = f.opt(f.map(f.enum { "MORN", "DAY", "NITE" },
    f.rec { rate = f.opt(f.numRange(0, 256)), slots = f.opt(f.list(slot)) })) }
local U = {
  pokemon = { fields = {
    id = id, name = f.str, dex = f.opt(f.int(1)), types = ids, baseStats = stats,
    catchRate = f.int(0, 255), baseExp = f.int(0), growthRate = id,
    level1Moves = ids, learnset = f.list(f.rec { level = level, move = id }),
    evolutions = f.list(evolution), tmhm = f.opt(ids), eggMoves = f.opt(ids),
    genderRatio = f.opt(f.int(0, 255)), eggCycles = f.opt(f.int(0, 255)),
    spriteFront = f.opt(f.path), spriteBack = f.opt(f.path), frontSize = f.opt(f.int(1, 7)),
    trueColor = f.opt(f.bool),
  } },
  moves = { fields = {
    id = id, name = f.str, type = id, power = f.int(0, 255), accuracy = f.int(0, 100),
    pp = f.int(0, 64), effect = f.opt(id),
    category = f.opt(f.enum { "physical", "special", "status" }),
    priority = f.opt(f.int(-7, 7)), description = f.opt(f.str),
  } },
  items = { fields = {
    id = id, name = f.str, price = f.int(0),
    index = f.opt(f.int(0, 65535)),
    machine = f.opt(f.rec { kind = f.str, move = id, number = f.int(0) }),
    effect = f.opt(id), ball = f.opt(id), tossable = f.opt(f.bool),
    needsTarget = f.opt(f.bool), description = f.opt(f.str),
  } },
  trainers = { fields = {
    id = id, name = f.str, pic = f.opt(f.path), baseMoney = f.opt(f.int(0)),
    battleTheme = f.opt(id), partyNames = f.opt(f.list(f.str)),
    parties = f.list(f.list(f.rec {
      species = id, level = level, item = f.opt(id), moves = f.opt(ids),
    })),
  } },
  encounters = { fields = { id = f.opt(id), grass = f.opt(area), water = f.opt(area) } },
}
for _, spec in pairs(U) do
  spec.fields.native = f.opt(f.any)
  spec.semantics = "record"
end
return U
