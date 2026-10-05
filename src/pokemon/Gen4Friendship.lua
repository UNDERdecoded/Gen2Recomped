-- PLATINUM'S WALKING FRIENDSHIP (pokeplatinum src/overlay005/field_control.c
-- Field_UpdateFriendship / Field_CalculateFriendship and src/pokemon.c
-- Pokemon_UpdateFriendship, FRIENDSHIP_EVENT_WALK_CYCLE).
--
-- Every 128th step each Pokemon in the party, on its own coin flip
-- (`LCRNG_Next() & 1` -- heads it is skipped), gains:
--   +1 (sFriendshipChangeTable's walk row is 1 in all three tiers)
--   +1 if it is in a Luxury Ball
--   +1 if its EGG LOCATION is where the party is standing -- the cartridge
--      compares MON_DATA_EGG_LOCATION, not the met location, against the
--      map's location name, and that is kept: a Pokemon caught on a route
--      gets no bonus there, one hatched from an egg received there does
--   then x1.5, rounded down, for a Soothe Bell (HOLD_EFFECT_FRIENDSHIP_UP)
-- capped at 255. Eggs are skipped.
--
-- The engine's generic rule (+2/+2/+1 by tier, every time) was Platinum's until
-- now.

local Gen4Friendship = {}

Gen4Friendship.LUXURY_BALL = 11
Gen4Friendship.CYCLE = 128

local function labelText(data, mapId)
  local def = data and data.maps and data.maps[mapId]
  local rec = data and data.gen4_area_popup
  local row = def and rec and rec.headers and rec.headers[tonumber(def.header) or -1]
  return row and row.text
end

-- One step. `rng(a, b)` like love.math.random. Answers true on a cycle.
function Gen4Friendship.step(data, save, mapDef, rng)
  rng = rng or math.random
  save.gen4FriendshipSteps = ((save.gen4FriendshipSteps or 0) + 1) % Gen4Friendship.CYCLE
  if save.gen4FriendshipSteps ~= 0 then return false end
  local Party = require("src.pokemon.Party")
  local here = mapDef and labelText(data, mapDef.id)
  for _, mon in ipairs(save.party or {}) do
    if mon.species and not Party.isEgg(mon) and rng(0, 1) == 0 then
      local def = data.pokemon and data.pokemon[mon.species]
      if mon.happiness == nil then mon.happiness = def and def.friendship or 70 end
      local gain = 1
      if tonumber(mon.ball) == Gen4Friendship.LUXURY_BALL or mon.ball == "LUXURY_BALL" then
        gain = gain + 1
      end
      if here and mon.eggLocation and labelText(data, mon.eggLocation) == here then
        gain = gain + 1
      end
      local item = mon.item and data.items and data.items[mon.item]
      if item and item.holdEffect == "FRIENDSHIP_UP" then
        gain = math.floor(gain * 150 / 100)
      end
      mon.happiness = math.min(255, mon.happiness + gain)
    end
  end
  return true
end

-- A SAVE MADE BEFORE PLATINUM POKEMON CARRIED FRIENDSHIP: give every party
-- and box Pokemon its species' base value, once. Eggs keep theirs (an egg's
-- friendship byte is its hatch counter).
function Gen4Friendship.migrate(data, save)
  if type(save) ~= "table" or save.gen4FriendshipSeeded then return 0 end
  local Party = require("src.pokemon.Party")
  local n = 0
  local function seed(mon)
    if type(mon) == "table" and mon.species and mon.happiness == nil
       and not Party.isEgg(mon) then
      local def = data and data.pokemon and data.pokemon[mon.species]
      mon.happiness = (def and (def.baseFriendship or def.friendship)) or 70
      n = n + 1
    end
  end
  for _, mon in ipairs(save.party or {}) do seed(mon) end
  for _, box in pairs(save.boxes or {}) do
    if type(box) == "table" then for _, mon in pairs(box) do seed(mon) end end
  end
  save.gen4FriendshipSeeded = true
  return n
end

return Gen4Friendship
