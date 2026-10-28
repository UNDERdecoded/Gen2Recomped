-- Public callback-name snapshot from Gen1Recomp API 3, commit
-- 79ea62f45fb2ea8f65d081a109431e4eb1bbdb36. Recognition is not availability:
-- Capabilities still requires a native Gen2Recomped call site.
local function names(text)
  local out = {}
  for name in text:gmatch("%S+") do
    out[name] = true
  end
  return out
end
local C = {}
C.hooks = names([[
battle.accuracy battle.bottom_ui_visible battle.catch_exp battle.caught_marker_visible
battle.charge_required battle.crit battle.damage battle.enemy_action
battle.enemy_switch_or_item battle.exp_award battle.field_residual battle.low_health_alarm
battle.menu_auxiliary battle.move_grid_navigation battle.overlay battle.run
battle.status_hud_visible battle.style battle.turn_order breeding.compatibility
catch.nickname catch.party_full catch.rate core.logic_speed
core.quit_to_launcher core.update encounter.fishing encounter.roll
encounter.species encounter.table evolution.check exp.gain
fieldmove.eligibility gender.roll held_item.trigger input.gamepad
input.key input.pointer input.step input.wheel
intro.oak_speech.build item.use link.fingerprint map.palette
movement.collision movement.speed music.select music.volume
phone.contact_list player.sprite pokemon.icon pokemon.level_visible
pokemon.sprite render.compose render.hud render.letterbox
render.output render.output_enabled render.viewport render.window
render.zones save.new_game save.write screen.render_visible
script.command shiny.roll trainer.before_battle trainer.party
transition.style ui.list_menu ui.naming.grid ui.options.rows
ui.party.grid_navigation ui.party.submenu ui.pc.items ui.start_menu.items
ui.title_menu.items warp.destination world.follower.spawn world.talk
world.tod zoom.range
]])
C.events = names([[
apricorn.converted assets.transformed battle.ball_thrown battle.battler_switched
battle.damage_dealt battle.ended battle.exp_gained battle.fainted
battle.move_used battle.started battle.status_inflicted battle.turn_ended
battle.turn_started breeding.egg_created bug_contest.scored checkpoint.restored
clock.day_changed discord.join_requested egg.hatched flag.changed
game.ready happiness.changed intro.boot.copyright intro.boot.gamefreak
intro.boot.movie intro.boot.movie_ended intro.boot.title intro.oak_speech.answered
intro.oak_speech.finished intro.oak_speech.started intro.oak_speech.step link.battle_ended
link.connected link.desync link.ended mail.read
mail.written map.entered map.exited map.reloaded
mod.options_changed mods.loaded music.started music.stopped
phone.call_received player.warped pokemon.before_give pokemon.caught
pokemon.evolved pokemon.level_up pokemon.move_learned pokemon.received
pokerus.infected radio.channel roamer.encountered roamer.moved
save.created save.loaded save.loading save.writing
screen.popped screen.pushed script.ended script.started
sound.played trade.completed unown.unlocked world.blacked_out
world.block_replaced world.boulder_moved world.interacted world.live_maps_preparing
world.live_maps_updated world.npc_spawned world.object_toggled world.stepped
world.tod_changed world.trainer_engaged
]])
return C
