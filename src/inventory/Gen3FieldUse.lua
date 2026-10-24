-- GBA field-use boundary. Effects/consumption precede the public result;
-- presentation is returned separately so post-next wrappers can replace text
-- without re-running an effect or committing the native UI too early.
local Runtime = require("src.mods.Runtime")
local Effects = require("src.inventory.ItemEffects")
local Bag = require("src.inventory.Bag")
local Strings = require("src.core.Strings")
local F = {}

local function keyFor(data, id, stable)
  local def = data.items and data.items[id]
  if def and def.key then
    return def.key
  end
  if stable and stable[id] then
    return stable[id].id
  end
  local key = Effects.alias(id, def)
  if type(key) == "string" and not key:match("^ITEM_%d+$") then
    return key
  end
  local name = def and (def.translationSourceName or def.name)
  return type(name) == "string" and name:upper():gsub("[^%w]+", "_") or tostring(id)
end

function F.kind(data, id, stable)
  local def = data.items and data.items[id]
  if not def then
    return "unknown"
  end
  if def.effect then
    return "mod"
  end
  local key, effect = keyFor(data, id, stable), Effects.gen3RecordFor(id, data) or {}
  if def.machine then
    return "tm"
  end
  if effect.levelUp or key == "RARE_CANDY" then
    return "level"
  end
  if effect.evolve or Effects.isStone(key) then
    return "evo"
  end
  if effect.ev then
    return "vitamin"
  end
  if effect.pp or effect.ppUp or effect.ppMax then
    return "pp"
  end
  if effect.revive or effect.sacredAsh or key == "REVIVE" or key == "MAX_REVIVE" then
    return "revive"
  end
  if effect.heal or Effects.healsHP(id) then
    return "heal"
  end
  if effect.cures or effect.cureAll or key == "ANTIDOTE" or key == "FULL_HEAL" then
    return "status"
  end
  if key:find("REPEL", 1, true) then
    return "repel"
  end
  if key:find("BIKE", 1, true) or key == "BICYCLE" then
    return "bike"
  end
  if key:match("_ROD$") then
    return "rod"
  end
  local kinds = {
    ESCAPE_ROPE = "escape",
    TOWN_MAP = "map",
    COIN_CASE = "coin_case",
    POWDER_JAR = "powder_jar",
    ITEMFINDER = "itemfinder",
    VS_SEEKER = "vs_seeker",
    POKE_FLUTE = "flute",
    BLACK_FLUTE = "black_white_flute",
    WHITE_FLUTE = "black_white_flute",
    TM_CASE = "tm_case",
    BERRY_POUCH = "berry_pouch",
    POKEBLOCK_CASE = "pokeblock_case",
    TEACHY_TV = "teachy_tv",
  }
  if kinds[key] then
    return kinds[key]
  end
  if Effects.isBall(id, def) or key:match("^X_") or key == "POKE_DOLL" then
    return "battle"
  end
  return "none"
end

local function refusal(game)
  return Strings("This isn't the time to use that!")
end
local function textOf(payload)
  return type(payload) == "table" and table.concat(payload, "\f") or nil
end

local function evaluate(game, id, slot, moveIndex)
  local stable = game.mods and game.mods._unifiedIdBase and game.mods._unifiedIdBase.items
  local kind, data, save = F.kind(game.data, id, stable), game.data, game.save
  local def, key, ow = data.items[id], keyFor(data, id, stable), game.overworld
  local p = { id = id, target = slot and save.party and save.party[slot], kind = kind }
  if not def then
    return false, "unknown", Strings("Unknown item."), p
  end
  if
    require("src.core.GameVersion").get() == "emerald"
    and (key == "POKE_FLUTE" or key == "TM_CASE" or key == "BERRY_POUCH")
  then
    return false, "none", refusal(game), p
  end
  local targeted = {
    heal = true,
    status = true,
    revive = true,
    pp = true,
    vitamin = true,
    level = true,
    evo = true,
    tm = true,
  }
  if targeted[kind] or (Effects.needsTarget(id, def) and not Effects.isBall(id, def)) then
    if not save.party or #save.party == 0 then
      return false, "noparty", Strings("There is no POKeMON."), p
    end
    if not slot then
      return false, "need_slot", Strings("Select a POKeMON."), p
    end
    if not p.target then
      return false, "noparty", Strings("There is no POKeMON."), p
    end
  end
  local effect = Effects.gen3RecordFor(id, data) or {}
  if kind == "pp" and not moveIndex and (effect.pp == "one" or effect.ppUp or effect.ppMax) then
    return false, "need_move", nil, p
  end
  if kind == "repel" and (tonumber(save.repelSteps) or 0) > 0 then
    return false, "repel", Strings("The REPEL's effect still lingers!"), p
  end
  if kind == "coin_case" or kind == "powder_jar" then
    p.result = "kept"
    return true,
      kind,
      kind == "coin_case" and Strings("Your Coins: %d", save.coins or 0) or Strings(
        "Powder: %d",
        save.berryPowder or 0
      ),
      p
  end
  if kind == "battle" then
    return false, kind, refusal(game), p
  end
  if kind == "tm" then
    local move = def.machine and def.machine.move
    local moveDef = move and data.moves and data.moves[move]
    if not moveDef then
      return false, "invalid", Strings("It won't have any effect."), p
    end
    local species, compatible = data.pokemon[p.target.species], false
    for _, allowed in ipairs(species and species.tmhm or {}) do
      if allowed == move then
        compatible = true
        break
      end
    end
    if not compatible then
      return false, "incompatible", Strings("That POKeMON can't learn this move."), p
    end
    for _, known in ipairs(p.target.moves or {}) do
      if known.id == move then
        return false, "knows", Strings("That move is already known."), p
      end
    end
    if #p.target.moves >= 4 then
      p.result, p.payload = def.machine.kind == "HM" and "learnkept" or "learn", move
      p.payloadIsData = true
      return false, "full", Strings("Choose a move to forget."), p
    end
    table.insert(p.target.moves, { id = move, pp = moveDef.pp })
    if def.machine.kind ~= "HM" then
      Bag.remove(save, id, 1)
      p.consumed = true
    end
    require("src.pokemon.Gen2Friendship").change(p.target, "LEARNMOVE")
    p.result = "kept"
    local name = p.target.nickname or species.name
    return true, "tm", Strings("%s learned %s!", name, moveDef.name), p
  end
  if kind == "bike" then
    local player = ow and ow.player
    if save.forcedBike then
      return false, kind, Strings("You can't dismount your BIKE here."), p
    end
    if
      not (ow and ow.map and ow.bikeAllowed and ow:bikeAllowed(ow.map.id))
      or (
        player
        and (
          player.surfing
          or player.underwater
          or (ow.map.runningBlockedAt and ow.map:runningBlockedAt(player.cellX, player.cellY))
        )
      )
    then
      return false, kind, refusal(game), p
    end
    save.onBike = not save.onBike
    save.bikeKind = save.onBike and (key == "ACRO_BIKE" and "acro" or key == "MACH_BIKE" and "mach" or nil)
      or nil
    require("src.core.Music").playMap(data, ow.map.id, save.onBike)
    p.result, p.closeBag = "kept", true
    return true, kind, nil, p
  end
  if kind == "rod" then
    local player, map = ow and ow.player, ow and ow.map
    local x, y
    if player and player.facingCell then
      x, y = player:facingCell()
    end
    if not (map and x and map:inBounds(x, y) and map:isWaterCell(x, y)) then
      return false, kind, refusal(game), p
    end
    p.result, p.closeBag, p.action = "kept", true, function()
      ow:goFishing(id)
    end
    return true, kind, nil, p
  end
  if kind == "escape" then
    local point = ow and ow.escapePoint and ow:escapePoint()
    if not (ow and ow.map and ow.map.def.allowEscaping == true and point) then
      return false, kind, refusal(game), p
    end
    Bag.remove(save, id, 1)
    p.consumed, p.closeBag, p.result = true, true, "kept"
    p.action = function()
      ow:beginTeleportOut(nil, { escape = true })
    end
    return true, kind, Strings("%s used %s!", save.player.name, def.name), p
  end
  if kind == "black_white_flute" then
    save.gen3Flute = key == "WHITE_FLUTE" and "white" or "black"
    p.result = "kept"
    return true, kind, Strings("%s used %s!", save.player.name, def.name), p
  end
  if kind == "flute" then
    local woke = false
    for _, mon in ipairs(save.party or {}) do
      if mon.status == "SLP" and not mon.isEgg then
        mon.status, mon.sleep, woke = nil, nil, true
      end
    end
    if woke then
      require("src.core.Sound").play(data, "Pokeflute")
    end
    p.result = "kept"
    return true, kind, Strings("Played the POKe FLUTE."), p
  end
  local result, payload, extra = Effects.use(data, save, id, p.target, nil, moveIndex, ow)
  p.result, p.payload, p.extra = result, payload, extra
  if result == "consumed" then
    Bag.remove(save, id, 1)
    p.consumed = true
  end
  local ok = result ~= "failed"
  if kind == "unknown" or kind == "none" then
    local mapped = {
      townmap = "map",
      pokeblock_case = "pokeblock_case",
      teachy_tv = "teachy_tv",
      itemfinder = "itemfinder",
      vs_seeker = "vs_seeker",
      learn = "tm",
      learnkept = "tm",
    }
    kind = mapped[result] or kind
  end
  if not ok and p.target then
    kind = "noeffect"
  end
  return ok, kind, textOf(payload), p
end

function F.call(game, id, slot, moveIndex)
  local prepared, nativeOk, nativeKind, nativeText
  local function native(_, _, item, targetSlot)
    nativeOk, nativeKind, nativeText, prepared = evaluate(game, item, targetSlot, moveIndex)
    return nativeOk, nativeKind, nativeText
  end
  -- Like the source producer, Game/slot/bag are engine handles; only the
  -- replacement item and party slot are accepted by the captured native use.
  local ok, kind, text = Runtime.call("item.use", native, game, nil, id, slot, game.save.inventory)
  if prepared and ok == nativeOk and kind == nativeKind then
    prepared.textChanged = text ~= nativeText
    if not prepared.payloadIsData then
      if prepared.textChanged then
        prepared.payload = type(text) == "string" and { text } or nil
      end
      if prepared.payload == nil and type(text) == "string" then
        prepared.payload = { text }
      end
    end
    prepared.text = text
    return ok, kind, text, prepared
  end
  local closes = { bike = true, rod = true, escape = true, on_field = true, teachy_tv = true }
  return ok,
    kind,
    text,
    {
      result = "failed",
      payload = type(text) == "string" and { text } or nil,
      text = text,
      closeBag = ok and closes[kind] or nil,
      custom = true,
      id = id,
      target = slot and game.save.party and game.save.party[slot],
    }
end
return F
