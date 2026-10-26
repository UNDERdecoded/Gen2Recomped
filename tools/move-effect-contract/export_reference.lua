package.path = "./?.lua;./?/init.lua;" .. package.path
local E = require("src.mods.UnifiedEffects")
local M1 = require("src.battle.g3u.EffectMap1")
local M2 = require("src.battle.g3u.EffectMap2")
local N = require("src.core.game3.battle.effect_ids")
local ids = {}
for _, t in ipairs({ M1.EFFECTS, M1.UNSUPPORTED, M2.EFFECTS, M2.UNSUPPORTED, N }) do
  for k in pairs(t) do
    ids[k] = true
  end
end
local out = { bindings = {}, read3 = {}, read2 = {}, variants = {}, reserved = {} }
for id in pairs(ids) do
  out.reserved[id] = true
end
for id, row in pairs(M1.EFFECTS) do
  out.variants[id] = { semantic = row.effect, chance = row.chance }
end
for id in pairs(ids) do
  local row = {}
  for gen = 1, 3 do
    local native, chance = E.write(id, gen)
    if native then
      local semantic = gen == 3 and native
        or gen == 2 and M2.EFFECTS[native] and M2.EFFECTS[native].effect
        or nil
      if gen == 2 and native == "EFFECT_BURN" then
        semantic = N.WILL_O_WISP
      end
      row[tostring(gen)] =
        { native = native, chance = type(chance) == "number" and chance or nil, semantic = semantic }
    end
  end
  if next(row) then
    out.bindings[id] = row
  end
end
for i = 0, 255 do
  out.read3[tostring(i)] = E.read(i, 3, {})
end
for id in pairs(M2.EFFECTS) do
  out.read2[id] = E.read(id, 2, {})
end
print(require("src.link.Json").encode(out))
