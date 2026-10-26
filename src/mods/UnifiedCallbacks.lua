local Api3Catalog = require("src.mods.Api3Catalog")
local Records = require("src.mods.CallbackRecords")
local EnemyActionContext = require("src.battle.EnemyActionContext")
local Ids = require("src.mods.UnifiedIds")
local C = {}
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function names(text)
  local out = {}
  for name in text:gmatch("%S+") do
    out[name] = true
  end
  return out
end
-- This is an audited boundary catalog, not a claim that every game executes
-- every seam. The source-catalog test requires a decision for each new seam.
C.hooks = names([[
 held_item.trigger
 shiny.roll gender.roll
 battle.accuracy battle.catch_exp battle.crit battle.damage battle.enemy_action battle.exp_award
 battle.low_health_alarm battle.overlay battle.run battle.status_hud_visible battle.turn_order catch.rate
 encounter.fishing encounter.roll encounter.species evolution.check exp.gain fieldmove.eligibility
 input.step intro.oak_speech.build link.fingerprint map.palette movement.collision movement.speed
 music.select music.volume player.sprite pokemon.icon pokemon.sprite render.compose render.hud
 render.letterbox render.zones save.new_game save.write script.command trainer.party transition.style
 ui.list_menu ui.naming.grid ui.options.rows ui.party.submenu ui.pc.items ui.start_menu.items
 ui.title_menu.items warp.destination world.tod zoom.range
]])
C.events = names([[
 assets.transformed battle.ball_thrown battle.battler_switched battle.damage_dealt battle.ended
 battle.exp_gained battle.fainted battle.move_used battle.started battle.status_inflicted battle.turn_ended
 battle.turn_started discord.join_requested flag.changed game.ready intro.birch_speech.finished
 intro.birch_speech.started intro.oak_speech.answered intro.oak_speech.finished intro.oak_speech.started
 intro.oak_speech.step link.connected link.desync link.ended map.entered map.exited map.reloaded
 mod.option_action mod.options_changed mods.loaded music.started music.stopped player.warped
 pokemon.before_give pokemon.caught pokemon.egg_hatched pokemon.evolved pokemon.level_up
 pokemon.move_learned pokemon.received save.created save.loaded save.loading save.writing screen.popped
 screen.pushed script.ended script.started sound.played trade.completed world.blacked_out
 world.block_replaced world.blocks_replaced world.boulder_moved world.interacted world.npc_spawned
 world.object_toggled world.stepped world.tick world.tod_changed world.trainer_engaged
]])
local positions = {
  ["shiny.roll"] = { "context" },
  ["gender.roll"] = { "context" },
  ["held_item.trigger"] = { "context" },
  ["battle.accuracy"] = { "context" },
  ["battle.damage"] = { "context" },
  ["battle.crit"] = { "context" },
  ["battle.run"] = { "context" },
  ["battle.catch_exp"] = { "context" },
  ["battle.low_health_alarm"] = { "context" },
  ["battle.exp_award"] = { "context" },
  ["exp.gain"] = { "context" },
  ["battle.turn_order"] = { "battler", "move", "battler", "move", "context" },
  ["battle.enemy_action"] = { false, "battler" },
  ["catch.rate"] = { "items", "mon", "species", "context" },
  ["trainer.party"] = { false, false, "trainerParty" },
  ["evolution.check"] = { false, "mon", "context", "context" },
  ["fieldmove.eligibility"] = { "moves", false },
  ["encounter.fishing"] = { "items", false, "candidates" },
  ["encounter.roll"] = { false, "context" },
  ["encounter.species"] = { "encounter", "context" },
  ["ui.party.submenu"] = { false, false, "mon", false },
  ["pokemon.sprite"] = { false, "context" },
  ["pokemon.icon"] = { false, "context" },
}
local results = {
  ["fieldmove.eligibility"] = "mon",
  ["battle.enemy_action"] = "action",
  ["trainer.party"] = "trainerParty",
  ["battle.turn_order"] = "battler",
  ["encounter.fishing"] = "encounter",
  ["encounter.roll"] = "encounter",
  ["encounter.species"] = "encounter",
}
-- These payloads are engine handles, repair flows or UI objects, not record
-- notifications. In particular, game.ready has a forwarding metatable.
local nativeEvents = names([[
 game.ready save.created save.loaded save.loading save.writing mods.loaded
 screen.popped screen.pushed intro.birch_speech.finished intro.birch_speech.started
 intro.oak_speech.answered intro.oak_speech.finished intro.oak_speech.started intro.oak_speech.step
 mod.option_action mod.options_changed
]])
local function custom(name)
  return type(name) == "string" and name:match("^mod%.[%w_%-]+%..+$") ~= nil
end
function C.install(loader, api, owner, generation)
  -- Capture pristine alias identities before Loader merges them into separate
  -- records. Each call still builds a fresh index, including later mods' IDs.
  local ids = Ids.new(loader)
  local api3 = (api.manifest.api or 1) >= 3
  local extra = api3 and Api3Catalog
  for _, kind in ipairs({ "pokemon", "moves", "items" }) do
    ids:entries(kind)
  end
  local function check(catalog, name)
    assert(
      type(name) == "string"
        and (
          catalog[name]
          or (extra and (catalog == C.events and extra.events[name] or catalog == C.hooks and extra.hooks[name]))
          or (catalog == C.events and custom(name))
        ),
      "unknown unified callback: " .. tostring(name)
    )
  end
  local function subscribe(once, name, callback, priority)
    check(C.events, name)
    assert(type(callback) == "function", "event callback must be a function")
    local wrapped = callback
    if not custom(name) and not nativeEvents[name] then
      wrapped = function(payload)
        local boundary = Records.new(loader, name, generation, api3)
        local public = boundary.view(payload, name == "pokemon.before_give" and "gift" or "context")
        local values = pack(callback(public))
        if name == "pokemon.before_give" then
          boundary.commit()
        end
        return unpack(values, 1, values.n)
      end
    end
    if once then
      return loader.events:once(name, wrapped, priority, owner)
    end
    return loader.events:on(name, wrapped, priority, owner)
  end
  api.events = {
    on = function(_, ...)
      return subscribe(false, ...)
    end,
    once = function(_, ...)
      return subscribe(true, ...)
    end,
    emit = function(_, name, payload)
      local prefix = "mod." .. owner .. "."
      assert(custom(name) and name:sub(1, #prefix) == prefix, "mods may only emit " .. prefix .. "* events")
      return loader.events:emit(name, payload)
    end,
  }
  api.hooks = {
    wrap = function(_, name, callback, priority)
      check(C.hooks, name)
      assert(type(callback) == "function", "hook callback must be a function")
      return loader.hooks:wrap(name, function(nextFn, ...)
        local boundary = Records.new(loader, name, generation, api3)
        local portableEnemy = api3 and generation == 3 and name == "battle.enemy_action"
        local roles = portableEnemy and { false, "enemySlot" } or positions[name] or {}
        local function translate(args)
          local out = { n = args.n }
          for i = 1, args.n do
            local role = roles[i]
            local v = args[i]
            if role == "enemySlot" then
              v = EnemyActionContext.publicId(args[1], v)
            elseif role == "items" or role == "moves" then
              v = boundary.read(role, v)
            elseif role then
              v = boundary.view(v, role)
            end
            out[i] = v
          end
          return out
        end
        local original = pack(...)
        local function rawArgs(args)
          local out = { n = args.n }
          for i = 1, args.n do
            local role, v = roles[i], args[i]
            if role == "enemySlot" then
              v = EnemyActionContext.nativeActor(args[1], v)
            elseif role == "items" or role == "moves" then
              v = boundary.native(role, v, original[i])
            elseif role then
              local identity = api3 and (name == "shiny.roll" or name == "gender.roll")
              v = boundary.restore(v, role, identity and original[i] or nil)
            end
            out[i] = v
          end
          if portableEnemy and args.n < 2 then
            out.n, out[2] = 2, EnemyActionContext.nativeActor(args[1], nil)
          end
          return out
        end
        local public = translate(original)
        local called, downstream, publicResult = false, nil, nil
        local active = true
        local function nextPublic(...)
          assert(active, "next is only valid during its hook callback")
          assert(not called or downstream, "next is already running")
          if not called then
            local args = select("#", ...) == 0 and public or pack(...)
            local raw = boundary.commit(function()
              return rawArgs(args)
            end)
            called = true
            if portableEnemy then
              downstream = pack(pcall(EnemyActionContext.call, raw[1], args[2], nextFn, unpack(raw, 1, raw.n)))
            else
              downstream = pack(pcall(nextFn, unpack(raw, 1, raw.n)))
            end
            if downstream[1] then
              boundary.refresh()
              publicResult = pack(unpack(downstream, 2, downstream.n))
              if results[name] then
                publicResult[1] = boundary.view(publicResult[1], results[name])
              end
            end
          end
          if not downstream[1] then
            error(downstream[2], 0)
          end
          return unpack(publicResult, 1, publicResult.n)
        end
        local invoked = pack(pcall(callback, nextPublic, unpack(public, 1, public.n)))
        active = false
        if not invoked[1] then
          boundary.close()
          error(invoked[2], 0)
        end
        local values = pack(unpack(invoked, 2, invoked.n))
        if called and not downstream[1] then
          boundary.close()
          error(downstream[2], 0)
        end
        local ok, err = pcall(boundary.commit, function()
          if results[name] then
            values[1] = boundary.restore(values[1], results[name])
          end
        end)
        boundary.close()
        if not ok then
          error(err, 0)
        end
        return unpack(values, 1, values.n)
      end, priority, owner)
    end,
  }
end
return C
