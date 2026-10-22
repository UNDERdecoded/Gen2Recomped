-- Closed portable gift rows; execute through native gift/bag/party/box commands.
local Ids = require("src.mods.UnifiedIds")
local G = { ARITY = { give_item = 5, give_pokemon = 5 } }
local function integer(n, lo, hi)
  return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi
end
local function id(s)
  return type(s) == "string" and #s > 0 and #s <= 256 and not s:find("%c")
end
local function text(s)
  return type(s) == "string" and #s <= 4096 and not s:find("%z")
end
function G.syntax(verb, row)
  if not id(row[2]) then
    return nil, "invalid gift id"
  end
  if verb == "give_item" then
    if #row < 2 or #row > 5 then
      return nil, "invalid command arity"
    end
    if row[3] ~= nil and not integer(row[3], 1, 999) then
      return nil, "invalid item count"
    end
    if row[4] ~= nil and row[4] ~= false and not text(row[4]) then
      return nil, "invalid gift text"
    end
    if row[5] ~= nil and not text(row[5]) then
      return nil, "invalid bag full text"
    end
  else
    if #row < 3 or #row > 5 then
      return nil, "invalid command arity"
    end
    if not integer(row[3], 1, 100) then
      return nil, "invalid gift level"
    end
    if row[4] ~= nil and type(row[4]) ~= "boolean" or row[5] ~= nil and type(row[5]) ~= "boolean" then
      return nil, "invalid gift option"
    end
  end
  return { row[1], row[2], row[3], row[4], row[5] }
end
function G.prepare(loader, game, world, rows)
  local ids = Ids.new(loader)
  local plans = {}
  local function validate(row)
    if G.ARITY[row[1]] then
      local kind = row[1] == "give_item" and "items" or "pokemon"
      local group, reason = ids:resolve(kind, row[2])
      if not group or not (game.data[kind] and game.data[kind][group.key]) then
        return nil, reason or "gift content unavailable"
      end
      local save = game.save
      if row[1] == "give_item" then
        if type(save.inventory) ~= "table" or save.bagOrder ~= nil and type(save.bagOrder) ~= "table" then
          return nil, "invalid inventory store"
        end
        for _, count in pairs(save.inventory) do
          if not integer(count, 0, 999999) then
            return nil, "invalid inventory count"
          end
        end
      elseif
        type(save.party) ~= "table"
        or type(save.pokedex) ~= "table"
        or type(save.pokedex.seen) ~= "table"
        or type(save.pokedex.owned) ~= "table"
      then
        return nil, "invalid gift party/dex store"
      end
      if row[1] == "give_pokemon" then
        if type(save.player) ~= "table" then
          return nil, "invalid gift player store"
        end
        if #save.party > 6 then
          return nil, "invalid gift party"
        end
        for index, mon in pairs(save.party) do
          if not integer(index, 1, #save.party) or type(mon) ~= "table" then
            return nil, "invalid gift party"
          end
        end
        for index = 1, #save.party do
          if type(save.party[index]) ~= "table" then
            return nil, "invalid gift party"
          end
        end
        for _, name in ipairs({ "boxes", "box", "boxNames" }) do
          if save[name] ~= nil and type(save[name]) ~= "table" then
            return nil, "invalid box store"
          end
        end
        if save.currentBox ~= nil and not integer(save.currentBox, 1, 65535) then
          return nil, "invalid box index"
        end
        for _, box in pairs(save.boxes or {}) do
          if type(box) ~= "table" then
            return nil, "invalid box store"
          end
        end
      end
      return group.key
    end
  end
  for i, row in ipairs(rows) do
    if G.ARITY[row[1]] then
      local key, reason = validate(row)
      if not key then
        return nil, "row " .. i .. ": " .. reason
      end
      plans[row] = key
    end
  end
  return function(ctx, row)
    local key = plans[row]
    if not key then
      error("unprepared gift", 0)
    end
    if not game.data[row[1] == "give_item" and "items" or "pokemon"][key] then
      error("gift content unavailable", 0)
    end
    local ready, reason = validate(row)
    if not ready then
      error(reason, 0)
    end
    local Commands = require("src.script.Commands")
    if row[1] == "give_item" then
      ctx.portableBagFullText = row[5]
      return Commands.give_item(ctx, key, row[3], row[4])
    end
    ctx.portableGiftText = row[5]
    return Commands.give_pokemon(ctx, key, row[3], row[4])
  end
end
return G
