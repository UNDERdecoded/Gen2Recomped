-- Availability of the existing API-2 surfaces, before a Game/overworld exists.
-- Keep callback names tied to native call sites, not to the permissive buses:
-- successfully subscribing to a name does not mean the engine ever fires it.
local GameVersion = require("src.core.GameVersion")
local Schemas = require("src.mods.Schemas")

local Capabilities = {}
local callbacks = { hooks = {}, events = {} }
local function add(surface, generations, names)
  for name in names:gmatch("%S+") do
    callbacks[surface][name] = generations
  end
end

-- Shared simulation, world, input, rendering and lifecycle code. A callback
-- need not fire on every action (e.g. an always-hit move skips accuracy).
add("hooks", "12345", [[
  battle.accuracy battle.bottom_ui_visible battle.catch_exp battle.crit battle.damage battle.enemy_action
  battle.exp_award battle.low_health_alarm battle.menu_auxiliary battle.move_grid_navigation battle.run battle.turn_order catch.rate core.logic_speed core.update
  encounter.fishing encounter.roll encounter.species evolution.check exp.gain
  fieldmove.eligibility input.key input.gamepad input.wheel input.step link.fingerprint map.palette movement.collision
  movement.speed music.select music.volume player.sprite pokemon.icon pokemon.sprite
  render.compose render.hud render.letterbox render.zones save.new_game save.write screen.render_visible
  script.command trainer.before_battle trainer.party transition.style ui.list_menu ui.options.rows
  ui.title_menu.items warp.destination world.talk world.tod zoom.range
]])
-- Screens have distinct implementations: Screens.lua aliases the DS party,
-- naming and start menus; those implementations do not call the GB/GBA hooks.
-- OverworldController:openPC bypasses ui.pc.items on Gen 3/4 (and Gen 5 uses
-- its own script PC). Gen4Battle paints its HUD through a separate seam and
-- does not dispatch battle.overlay, unlike BattleState/Gen3Battle/WideBattle.
add("hooks", "123", "battle.overlay ui.naming.grid ui.party.submenu ui.start_menu.items")
add("hooks", "12", "ui.pc.items")
add("hooks", "12345", "battle.status_hud_visible")
add("hooks", "123", "pokemon.level_visible ui.party.grid_navigation")
add("hooks", "123", "world.follower.spawn")
add("hooks", "13", "item.use")
add("hooks", "23", "held_item.trigger")
add("hooks", "123", "encounter.table battle.charge_required battle.caught_marker_visible battle.field_residual")
add("hooks", "12", "intro.oak_speech.build")

add("events", "12345", [[
  world.live_maps_preparing world.live_maps_updated
  assets.transformed battle.ball_thrown battle.battler_switched battle.damage_dealt
  battle.ended battle.exp_gained battle.fainted battle.move_used battle.started
  battle.status_inflicted battle.turn_ended battle.turn_started discord.join_requested
  flag.changed game.ready link.connected link.desync link.ended map.entered map.exited
  map.reloaded mod.option_action mod.options_changed mods.loaded music.started
  music.stopped player.warped pokemon.before_give pokemon.caught pokemon.evolved
  pokemon.level_up pokemon.move_learned pokemon.received save.created save.loaded
  save.loading save.writing screen.popped screen.pushed script.ended script.started
  sound.played trade.completed world.blacked_out world.block_replaced
  world.blocks_replaced world.boulder_moved world.interacted world.npc_spawned
  world.object_toggled world.stepped world.tick world.tod_changed world.trainer_engaged
]])
add("events", "2345", "pokemon.egg_hatched")
add("events", "12", [[
  intro.oak_speech.answered intro.oak_speech.finished intro.oak_speech.started
  intro.oak_speech.step
]])
add("events", "3", "intro.birch_speech.started intro.birch_speech.finished")

-- Data:applyDefaults selects BirchSpeech on Emerald, Gen3OakSpeechFRLG on
-- FireRed, and no OakSpeech on Prism. DS imports select their own intros.
local function nativeVersion(name, version)
  if name:match("^intro%.birch_speech%.") then return version == "emerald" end
  if name:match("^intro%.oak_speech%.") then return version ~= "prism" end
  return true
end

-- Public WorldAPI methods only; constructors, internal helpers and methods
-- on returned NPC handles are not mod.world methods. These remain callable
-- at the title screen, returning their normal "no overworld"/"no save" error.
-- Elevation readers can return "map carries no elevation" on any dataset.
local world = {}
for name in ([[
  overworld current warpTo toggleObject setFlag getFlag replaceBlock spawnNpc
  removeNpc loadedMaps elevationInfo elevationAt terrainAt elevationRanks heightAt
  elevationGrid npc queueScript invalidateMap
]]):gmatch("%S+") do world[name] = true end

function Capabilities.supports(surface, name, version)
  if surface ~= "content" and surface ~= "world"
      and surface ~= "hooks" and surface ~= "events" then
    return false, "unsupported capability surface: " .. tostring(surface)
  end
  if type(name) ~= "string" or name == "" then
    return false, "capability name must be a non-empty string"
  end
  local info = GameVersion.VERSIONS[version]
  if not info then return false, "unknown game version: " .. tostring(version) end
  if surface == "content" then
    -- Every loader builds the same API-2 registries from Schemas. This says
    -- the registration API exists, not that record shapes/IDs are portable.
    if Schemas.REGISTRIES[name] then return true end
  elseif surface == "world" then
    if world[name] then return true end
  else
    -- A mod may listen to another mod's namespace without that mod installed;
    -- this only promises the bus supports it, never that a producer is present.
    if surface == "events" and name:match("^mod%.[%w_%-]+%..+") then return true end
    local gens = callbacks[surface][name]
    if gens then
      if gens:find(tostring(info.generation), 1, true) and nativeVersion(name, version) then
        return true
      end
      return false, ("%s capability %s has no native call site in %s")
        :format(surface, name, version)
    end
  end
  return false, ("unknown %s capability: %s"):format(surface, name)
end

return Capabilities
