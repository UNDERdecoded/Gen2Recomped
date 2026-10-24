local F = {}
function F.new(root, backend, version, api, format, mode)
  local snapshot
  local f = dofile(root .. "/tests/charge_required/fixture.lua").new(
    root,
    backend,
    version,
    api,
    format,
    mode == "no-mod",
    mode == "rollback" or (mode == "invalid" and api >= 2),
    "portable_held_content",
    function(data, gen)
      data.items = data.items or {}
      if backend == "gen2" then
        data.constants.generation = gen
      end
      for id, effect in pairs({
        LEFTOVERS = 3,
        BERRY = 1,
        QUICK_CLAW = 74,
        BRIGHTPOWDER = 77,
        FOCUS_BAND = 79,
        DRAGON_FANG = 0,
        DRAGON_SCALE = 64,
      }) do
        local native = backend == "gen1" and gen == 2
        local key = backend == "gen2"
            and gen == 2
            and ({
              LEFTOVERS = "ITEM_146",
              BERRY = "ITEM_173",
              QUICK_CLAW = "ITEM_073",
              BRIGHTPOWDER = "ITEM_003",
              FOCUS_BAND = "ITEM_112",
              DRAGON_FANG = "ITEM_144",
              DRAGON_SCALE = "ITEM_151",
            })[id]
          or id
        data.items[key] = {
          id = key,
          name = id:gsub("_", " "),
          price = 100,
          heldEffect = native and dofile(root .. "/tests/held_content/names.lua")[effect] or effect,
        }
        if id == "BERRY" then
          data.items[key].key = "ORAN_BERRY"
        end
        data.items[key][native and "heldParameter" or "heldParam"] = id == "BERRY" and 10 or 0
      end
      if backend == "gen1" and gen == 2 then
        local Items = require("src.core.gen2.ItemEffects")
        data.gen2HeldItems = Items.heldItemsFrom(data.items)
        snapshot = Items.heldSnapshot(data.gen2HeldItems)
      end
    end,
    function(files)
      local Json = require("src.link.Json")
      local path = "mods/portable_held_content/"
      local manifest = Json.decode(files[path .. "manifest.json"])
      manifest.games = { "gen1", "gen2", "gen3" }
      if require("src.core.GameVersion").generation() >= 4 then
        manifest.games = { version }
      end
      manifest.content_format = format
      files[path .. "manifest.json"] = Json.encode(manifest)
      files[path .. "case.txt"] = mode
      if mode == "stack" then
        files["mods/held_overlay/manifest.json"] = Json.encode({
          id = "held_overlay",
          name = "Held overlay",
          version = "1.0.0",
          api = api,
          games = { "gen2" },
          gen2compat = api < 3 and true or nil,
          content_format = format,
          dependencies = { "portable_held_content" },
          entry = "main.lua",
        })
        files["mods/held_overlay/main.lua"] =
          'local mod=...; mod.content.held_items:patch("LEFTOVERS", {heldParameter=9})'
      end
    end
  )
  if backend == "gen1" and f.gen == 2 then
    -- The production Game2 load bridge runs after the real registry merge.
    require("src.core.gen2.ItemEffects").applyHeldItems(f.data, snapshot)
  end
  function f.nativeItem(item)
    if backend ~= "gen2" or f.gen ~= 2 then
      return item
    end
    local id = require("src.mods.UnifiedIds").new(f.result.loader):resolve("items", item)
    return id and id.key or item
  end
  function f.run(item, hp)
    local step = f.fresh("TACKLE")
    f.battle = step.battle
    local p = backend == "gen1" and f.gen == 2 and f.battle.player or f.battle.player.mon
    p.hp, p.stats.hp, p.maxHp, p.item = hp or 100, 400, 400, f.nativeItem(item or "LEFTOVERS")
    f.battle.queue, f.battle.nextInsert = {}, 0
    if backend == "gen1" and f.gen == 2 then
      f.battle:betweenTurnEffects()
    else
      f.battle:endOfTurn()
    end
    return p.hp, p.item
  end
  function f.read(item)
    local step = f.fresh("TACKLE")
    if backend == "gen1" then
      step.battle.player.item = item
      return step.battle:heldEffect(step.battle.player)
    end
    step.battle.player.mon.item = f.nativeItem(item)
    local effect, amount = require("src.battle.HeldItems").effect(f.data, step.battle.player)
    return require("src.battle.HeldItemRead").goldPublic(effect), amount
  end
  return f
end
return F
