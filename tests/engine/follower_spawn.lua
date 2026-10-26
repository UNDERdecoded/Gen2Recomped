package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Fixture, Cases = dofile("tests/follower/fixture.lua"), dofile("tests/follower/cases.lua")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local gen, e = f.gen, f.e
    T.eq(e.api:supports("hooks", "world.follower.spawn"), gen <= 3, "honest native generation capability")
    if gen <= 3 then
      Cases.run(f)
      -- Preserve unrelated actors, native map seam identity and in-flight
      -- interpolation, including the trail's rebase alias.
      local off = e.api.hooks:wrap("world.follower.spawn", function()
        return true
      end, 100)
      local bystander = { id = "native-object" }
      f.world.npcs[#f.world.npcs + 1] = bystander
      f.world.entities[#f.world.entities + 1] = bystander
      f.tick()
      local npc = f.current()
      local trail = f.world.pikachuTrail
      local tx, ty = trail.x, trail.y
      f.world.cast = { "stale" }
      f.enter({ keepPikachu = npc })
      T.eq(f.current(), npc, "connection retains the actual companion")
      T.eq(f.world.pikachuTrail, trail, "connection retains buffered trail")
      T.eq(f.world.cast, nil, "map entry invalidates entity cast")
      f.controller.rebase(f.world, -3, 2)
      T.eq(f.world.pikachuTrail.x, tx - 3, "rebase mutates trail x in place")
      T.eq(f.world.pikachuTrail.y, ty + 2, "rebase mutates trail y in place")
      T.eq(npc.px, npc.cellX * 16, "rebased native pixel x agrees with cell")
      if gen >= 2 then
        T.eq(f.world.followerTrail, trail, "optional companion shares rebase alias")
        T.eq(
          f.controller.talk(f.game, f.world, npc),
          false,
          "optional companion cannot enter Yellow dialogue"
        )
      end
      off()
      local deny = e.api.hooks:wrap("world.follower.spawn", function()
        return false
      end, 100)
      f.tick()
      T.eq(f.world.npcs[1], bystander, "denial preserves unrelated native NPC")
      T.eq(f.world.entities[2], bystander, "denial preserves unrelated draw entry")
      deny()
      if gen >= 2 then
        -- Fallback artwork must not add a content alias or share the player's
        -- mutable renderer. This is an asset seam, not an alternative mod API.
        f.game.data.sprites.SPRITE_PIKACHU = nil
        local def = f.player.spriteDef
        f.player.spriteDef = nil
        f.player.sprite = require("src.render.SpriteRenderer").new(def, "fixture-player")
        local allow = e.api.hooks:wrap("world.follower.spawn", function()
          return true
        end, 100)
        f.enter()
        T.eq(f.current().sprite.def, def, "missing optional sheet uses player definition")
        T.neq(f.current().sprite, f.player.sprite, "follower owns a separate renderer")
        T.eq(f.game.data.sprites.SPRITE_PIKACHU, nil, "fallback never mutates content registry")
        if gen == 3 then
          f.player.cellX, f.player.cellY, f.player.px, f.player.py = 20, 20, 320, 320
          f.tick()
          T.eq(f.current().cellX, 20, "same-map GBA teleport resets companion x")
          T.eq(f.current().cellY, 20, "same-map GBA teleport resets companion y")
        end
        allow()
      end
    else
      local escort = { id = "scripted-escort", gen4Follower = true }
      f.world.npcs, f.world.entities = { escort }, { f.player, escort }
      local calls = 0
      local off = e.api.hooks:wrap("world.follower.spawn", function()
        calls = calls + 1
        return true
      end)
      f.enter()
      f.tick()
      T.eq(calls, 0, "DS has no promised follower producer")
      T.eq(f.world.npcs[1], escort, "DS native escort is untouched")
      off()
    end
    f.close()
    local failed = Fixture.new(".", "gen2", version, mode[1], mode[2], true)
    T.check(#failed.result.errors > 0, "entry rollback is reported")
    failed.tick()
    T.eq(failed.current() ~= nil, version == "yellow", "failed mod leaves native follower default")
    for _, entry in ipairs(Runtime.hooks.chains["world.follower.spawn"] or {}) do
      T.check(entry.owner ~= "portable_follower", "entry rollback removes owned hook")
    end
    failed.close()
  end
end
Version.set(old)
T.finish("portable native follower predicate")
