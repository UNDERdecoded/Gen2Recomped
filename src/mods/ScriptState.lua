-- Synchronous portable script actions over the host's native save/party/bag.
local Ids = require("src.mods.UnifiedIds")
local Version = require("src.core.GameVersion")
local S = {}
S.ARITY = {
  give_money = 2,
  take_money = 2,
  check_money = 2,
  take_coins = 2,
  check_item = 2,
  take_item = 3,
  check_dex_owned = 2,
  mark_seen = 2,
  heal_party = 1,
}
local function integer(value, minimum, maximum)
  return type(value) == "number"
    and value == value
    and value % 1 == 0
    and value >= minimum
    and value < math.huge
    and (not maximum or value <= maximum)
end
local function identifier(value)
  return type(value) == "string" and #value > 0 and #value <= 256 and not value:find("%c")
end
function S.syntax(verb, source)
  local n = S.ARITY[verb]
  local minimum = (verb == "take_item" or verb == "check_dex_owned") and 2 or n
  if verb == "check_dex_owned" then
    minimum = 1
  end
  if #source < minimum or #source > n then
    return nil, "invalid command arity"
  end
  if verb == "check_item" or verb == "take_item" or verb == "mark_seen" then
    if not identifier(source[2]) then
      return nil, "invalid content id"
    end
    if verb == "take_item" and source[3] ~= nil and not integer(source[3], 1, 999) then
      return nil, "invalid item count"
    end
  elseif verb ~= "heal_party" then
    if
      not (verb == "check_dex_owned" and source[2] == nil) and not integer(source[2], 0, 9007199254740991)
    then
      return nil, "invalid script amount"
    end
  end
  return { verb, source[2], source[3] }
end
local function tableOrNil(value)
  return value == nil or type(value) == "table"
end
function S.prepare(loader, game, world, rows)
  local ids = Ids.new(loader)
  local plans = {}
  local save = game.save
  local function number(value)
    return value == nil or integer(value, 0, 9007199254740991)
  end
  local function validate(row)
    local verb = row[1]
    if S.ARITY[verb] then
      local reason, key
      if verb == "give_money" or verb == "take_money" or verb == "check_money" then
        if not number(save.money) then
          reason = "invalid money store"
        elseif
          verb == "give_money"
          and Version.generation() == 1
          and not integer((save.money or 0) + row[2], 0, 9007199254740991)
        then
          reason = "money overflow"
        end
      elseif verb == "take_coins" then
        if not number(save.coins) then
          reason = "invalid coin store"
        end
      elseif verb == "check_item" or verb == "take_item" or verb == "mark_seen" then
        local kind = verb == "mark_seen" and "pokemon" or "items"
        local group, why = ids:resolve(kind, row[2])
        if not group or not (game.data[kind] and game.data[kind][group.key]) then
          reason = why or "content unavailable"
        else
          key = group.key
        end
        if not reason and kind == "items" then
          if
            type(save.inventory) ~= "table"
            or not number(save.inventory[key])
            or not tableOrNil(save.bagOrder)
          then
            reason = "invalid inventory store"
          end
        end
      end
      if verb == "mark_seen" or verb == "check_dex_owned" then
        local dex = save.pokedex
        if
          not tableOrNil(dex)
          or dex and (not tableOrNil(dex.seen) or not tableOrNil(dex.owned) or not tableOrNil(dex.caught))
        then
          reason = "invalid pokedex store"
        end
      elseif verb == "heal_party" then
        if type(save.party) ~= "table" then
          reason = "invalid party"
        else
          for _, mon in ipairs(save.party) do
            if
              type(mon) ~= "table"
              or type(mon.stats) ~= "table"
              or not integer(mon.stats.hp, 1, 65535)
              or not tableOrNil(mon.moves)
            then
              reason = "invalid party"
              break
            end
            for _, move in ipairs(mon.moves or {}) do
              if type(move) ~= "table" or not (game.data.moves and game.data.moves[move.id]) then
                reason = "invalid party move"
                break
              end
            end
          end
        end
      end
      if reason then
        return nil, reason
      end
      return { key = key }
    end
  end
  for i, row in ipairs(rows) do
    if S.ARITY[row[1]] then
      local plan, reason = validate(row)
      if not plan then
        return nil, "row " .. i .. ": " .. reason
      end
      plans[row] = plan
    end
  end
  return function(ctx, row)
    local verb, a = row[1], row[2]
    local plan = plans[row]
    if not plan then
      return false
    end
    -- Revalidate live stores too: another mod can mutate them while this script waits.
    local checked, reason = validate(row)
    if not checked then
      error(reason, 0)
    end
    if verb == "give_money" or verb == "take_money" then
      local value = math.max(0, (save.money or 0) + (verb == "give_money" and a or -a))
      if Version.generation() ~= 1 then
        value = math.min(999999, value)
      end
      save.money = value
    elseif verb == "check_money" then
      ctx.lastCheck = (save.money or 0) >= a
    elseif verb == "take_coins" then
      save.coins = math.max(0, (save.coins or 0) - a)
    elseif verb == "check_item" then
      ctx.lastCheck = (save.inventory[plan.key] or 0) > 0
    elseif verb == "take_item" then
      local n = math.min(row[3] or 1, save.inventory[plan.key] or 0)
      if n > 0 then
        require("src.inventory.Bag").remove(save, plan.key, n)
      end
    elseif verb == "mark_seen" then
      save.pokedex = save.pokedex or {}
      save.pokedex.seen = save.pokedex.seen or {}
      save.pokedex.seen[plan.key] = true
    elseif verb == "check_dex_owned" then
      local dex = save.pokedex
      local n = 0
      for _, value in pairs(dex and (dex.owned or dex.caught) or {}) do
        if value then
          n = n + 1
        end
      end
      ctx.lastCheck = n >= (a or 1)
    elseif verb == "heal_party" then
      for _, mon in ipairs(save.party) do
        require("src.pokemon.Pokemon").heal(mon, game.data.moves)
      end
    end
    return true
  end
end
return S
