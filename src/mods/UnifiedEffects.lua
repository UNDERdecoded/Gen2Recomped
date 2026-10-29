-- Canonical effect IDs over this host's shared native battle handlers.
local C = require("src.mods.MoveEffectContract")
local E = {}
local numbers, nativeNames, variants = {}, {}, {}
for number in pairs(C.native3) do
  numbers[#numbers + 1] = tonumber(number)
end
table.sort(numbers)
for _, number in ipairs(numbers) do
  for _, name in ipairs(C.native3[tostring(number)]) do
    if nativeNames[name] == nil then
      nativeNames[name] = number
    end
  end
end
for id in pairs(C.variants) do
  variants[#variants + 1] = id
end
table.sort(variants)
local function native(row, gen, chance)
  if gen == 1 then
    return row.native
  end
  local names = C.native3[tostring(row.semantic)]
  if not names then
    return nil
  end
  return names[2] and (chance or row.chance or 0) > 10 and names[2] or names[1]
end
local function opaque(value, gen)
  return "native:" .. gen .. ":" .. tostring(value)
end
function E.chance(raw, gen)
  if gen ~= 2 and gen ~= 3 then
    return nil
  end
  if type(raw.effectChance) == "number" then
    return math.max(0, math.min(100, math.floor(raw.effectChance * 100 / 256 + 0.5)))
  end
  return gen == 3 and raw.secondaryChance or nil
end
function E.read(value, gen, raw)
  if value == nil then
    return nil
  end
  if gen == 1 or gen > 3 then
    return type(value) == "string" and value or nil
  end
  raw = raw or {}
  local probability = E.chance(raw, gen)
  local authored = raw._api3EffectId
  local binding = type(authored) == "string" and C.bindings[authored]
  if binding and binding[tostring(gen)] then
    local row = binding[tostring(gen)]
    for _, name in ipairs(C.native3[tostring(row.semantic)] or {}) do
      if name == value then
        return authored
      end
    end
  end
  if authored == value and not C.reserved[authored] then
    return authored
  end
  local semantic = nativeNames[value]
  if gen == 3 and type(raw.gen3Effect) == "number" then
    local names = C.native3[tostring(raw.gen3Effect)]
    for _, name in ipairs(names or {}) do
      if name == value then
        semantic = raw.gen3Effect
      end
    end
  elseif value == "HEAL_EFFECT" and raw.id == "REST" then
    semantic = 37
  end
  if not semantic then
    return opaque(value, gen)
  end
  for _, id in ipairs(variants) do
    local row = C.variants[id]
    if row.semantic == semantic and row.chance == probability and C.bindings[id][tostring(gen)] then
      return id
    end
  end
  local id = C.read3[tostring(semantic)]
  if id and C.bindings[id] and C.bindings[id][tostring(gen)] then
    return id
  end
  return opaque(value, gen)
end
function E.write(id, gen, old, registered)
  if type(id) ~= "string" or id == "" then
    return nil, "move effect must be a string id"
  end
  id = ({ HIT = "NO_ADDITIONAL_EFFECT", SLEEP = "SLEEP_EFFECT" })[id] or id
  if old and (id == E.read(old.effect, gen, old) or id == opaque(old.effect, gen)) then
    return { effect = old.effect }, false
  end
  if gen > 3 then
    return nil, "changing move effects has no native adapter for this generation"
  end
  if id:match("^native:") then
    return nil, "native effect token requires its original record"
  end
  local binding = C.bindings[id]
  local row = binding and binding[tostring(gen)]
  if not row then
    if binding or C.reserved[id] or not registered(id) then
      return nil, "effect has no native handler: " .. id
    end
    return { effect = id, _api3EffectId = gen > 1 and id or nil }, true
  end
  if
    gen > 1
    and (
      (row.semantic == 37 and (not old or old.id ~= "REST"))
      or row.semantic == 32 and old and old.id == "REST"
      or row.semantic == 130 and (not old or old.id ~= "SONICBOOM")
      or row.semantic == 41 and old and old.id == "SONICBOOM"
    )
  then
    return nil, "native effect depends on move identity: " .. id
  end
  local target = native(row, gen)
  if not target or not registered(target) then
    return nil, "effect has no native handler: " .. id
  end
  local out = { effect = target }
  if gen > 1 then
    out._api3EffectId = id
    out.probability = row.chance
    out.gen3Effect = gen == 3 and row.semantic or nil
  end
  return out, true
end
return E
