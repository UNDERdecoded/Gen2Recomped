-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BATTLE BACK PICS A PLAYER CAN WEAR (MY LOOK -> BATTLE BACK).
--
-- Every choice is a back pic the running game's own import already wrote;
-- nothing here names a file of its own or ships a picture:
--   * Gen 3 (R/S/E, FR/LG): constants.gen3TrainerBack.images[k].pic -- the
--     whole gTrainerBackPicTable (the protagonists, the other games' players,
--     and the stand-ins like Wally / Steven), each with its throw strip
--   * Platinum / HGSS / Black / White: gen4_trainer_sprites.backs[class] --
--     every trainer back the cartridge carries, each with its throw strip
--     (backThrows, keyed by the still's path)
--   * plus the save's own protagonist forms (field.playerForms[g].back)
-- Game Boy games have no list here (their backs are 4-shade stills of the
-- player and the old man only), so the row is not shown there.
--
-- The choice is saved as the back pic's cache path in the per-game look
-- (save.options.looks[game].b) and re-checked against this list every time a
-- battle starts: a path the cache no longer has is simply ignored.

local BattleBacks = {}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do if tonumber(k) then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
  return keys
end

local function pathOf(v)
  if type(v) == "string" then return v end
  if type(v) == "table" then
    if type(v.path) == "string" then return v.path end
    if type(v.pic) == "string" then return v.pic end
  end
  return nil
end

-- { {path =, label =, gen3 = index|nil}, ... } for this game's cache
function BattleBacks.list(data)
  local out, seen = {}, {}
  if type(data) ~= "table" then return out end
  local forms = data.field and data.field.playerForms
  local mine = {}
  if type(forms) == "table" then
    for _, g in ipairs({ "boy", "girl" }) do
      local f = forms[g]
      if type(f) == "table" and type(f.back) == "string" then mine[f.back] = g end
    end
  end
  local function add(path, gen3)
    if type(path) ~= "string" or path == "" or seen[path] then return end
    seen[path] = true
    out[#out + 1] = { path = path, gen3 = gen3, mine = mine[path] }
  end
  local g3 = data.constants and data.constants.gen3TrainerBack
  if type(g3) == "table" and type(g3.images) == "table" then
    for _, k in ipairs(sortedKeys(g3.images)) do add(pathOf(g3.images[k]), tonumber(k)) end
  end
  local ts = data.gen4_trainer_sprites
  if type(ts) == "table" and type(ts.backs) == "table" then
    for _, k in ipairs(sortedKeys(ts.backs)) do add(pathOf(ts.backs[k])) end
  end
  for path in pairs(mine) do add(path) end
  -- labels: the protagonists by gender, the rest numbered in cartridge order
  local n = 0
  for _, e in ipairs(out) do
    if e.mine == "boy" then e.label = "BOY"
    elseif e.mine == "girl" then e.label = "GIRL"
    else n = n + 1 e.label = ("TRAINER %d"):format(n) end
  end
  return out
end

-- is `path` one of this cache's back pics?  -> its entry, or nil
function BattleBacks.find(data, path)
  if type(path) ~= "string" then return nil end
  for _, e in ipairs(BattleBacks.list(data)) do
    if e.path == path then return e end
  end
  return nil
end

-- a saved value, checked (shape only; the cache check is find())
function BattleBacks.clean(v)
  if type(v) ~= "string" or #v > 160 then return nil end
  if not v:match("^assets/generated/[%w_%-/%.]+%.png$") then return nil end
  if v:find("..", 1, true) then return nil end
  return v
end

return BattleBacks
