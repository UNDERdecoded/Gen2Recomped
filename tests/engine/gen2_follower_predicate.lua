package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
require("src.core.ModCompat").install()
local Follower = require("src.world.gen2.Follower")
local Fixture = dofile("tests/follower/fixture.lua")
local oldVersion = Version.get()
T.eq(Follower, require("src.world.OptionalFollower"), "alias is the actual native companion")

-- Use the real mod loader, native NPCs, maps, interpolation and map-entry
-- producer. Only cartridge art/data and the outer application are fixtures.
local function load(f, failing)
  local entry = [[
    local mod = ...
    local F = require("src.world.gen2.Follower")
    mod.exports.api = mod
    mod.exports.allow, mod.exports.calls = false, 0
    local previous = F.setShouldSpawn(function(game, world)
      mod.exports.calls = mod.exports.calls + 1
      mod.exports.game, mod.exports.world = game, world
      return mod.exports.allow
    end)
    mod.exports.previous = previous
  ]]
  if failing then entry = entry .. '\nerror("intentional follower entry failure")' end
  return T.sdk.loadMods({ "mods/follower_setter" }, {
    data = T.fixtures.fresh(),
    fs = T.sdk.memfs({
      ["mods/follower_setter/manifest.json"] = [[{
        "id":"follower_setter","name":"Native follower setter",
        "version":"1.0.0","api":2,"entry":"main.lua","affects_link":false
      }]],
      ["mods/follower_setter/main.lua"] = entry,
    }),
  })
end

for _, version in ipairs({ "gold", "silver", "crystal", "prism" }) do
  local f = Fixture.new(".", "gen2", version, 2, "native")
  f.close() -- remove the fixture's portable hook before loading the setter mod
  local nativeDefault = Follower.setShouldSpawn(nil)
  local result = load(f)
  T.eq(#result.errors, 0, "legacy setter mod loads on " .. version)
  local e = result.loader.exports.follower_setter
  T.eq(e.previous, nativeDefault, "setter returns the actual previous predicate")
  f.tick()
  T.eq(Follower.current(f.world), nil, "false predicate keeps vanilla companion absent")
  T.eq(e.game, f.game, "predicate receives native game")
  T.eq(e.world, f.world, "predicate receives native world")
  for _, value in ipairs({ true, 0, "" }) do
    e.allow = value
    f.tick()
    local npc = Follower.current(f.world)
    T.check(npc ~= nil, "Lua-truthy predicate spawns real native NPC")
    T.eq(npc, f.controller.current(f.world), "native controller and alias share the same NPC")
    T.eq(npc, f.world.follower, "world references that same companion")
    T.eq(npc.passable, true, "optional companion cannot block native movement")
    T.eq(f.world.npcs[#f.world.npcs], npc, "normal NPC loop owns companion updates")
    T.eq(f.world.entities[#f.world.entities], npc, "normal draw list owns companion")
  end
  local npc = Follower.current(f.world)
  local bystander = { id = "ordinary-object" }
  f.world.npcs[#f.world.npcs + 1] = bystander
  f.world.entities[#f.world.entities + 1] = bystander
  local startX = npc.px
  for _ = 1, 2 do
    local p = f.player
    p.targetX, p.targetY, p.moving, p.facing = p.cellX + 1, p.cellY, true, "right"
    for frame = 1, 4 do f.tick() end
    p.cellX, p.px, p.targetX, p.targetY, p.moving = p.cellX + 1, (p.cellX + 1) * 16, nil, nil, false
  end
  T.check(npc.px > startX, "native interpolation follows committed player destinations")
  local trail = f.world.followerTrail
  f.enter({ keepFollower = npc })
  T.eq(Follower.current(f.world), npc, "native connection retains companion identity")
  T.eq(f.world.followerTrail, trail, "connection retains the live buffered trail")
  local x, y = npc.px, npc.py
  f.controller.rebase(f.world, -2, 1)
  T.eq(npc.px, x - 32, "connection rebase moves real companion x")
  T.eq(npc.py, y + 16, "connection rebase moves real companion y")
  local off = e.api.hooks:wrap("world.follower.spawn", function() return false end, 100)
  f.tick()
  T.eq(Follower.current(f.world), nil, "public hook can deny the legacy predicate")
  T.eq(f.world.npcs[1], bystander, "denial retains unrelated NPC")
  off()
  f.tick()
  T.check(Follower.current(f.world) ~= nil, "unsubscribe returns to legacy predicate")
  require("src.mods.Loader").teardown()
  result.release()
  T.eq(Follower.setShouldSpawn(nil), nativeDefault, "real mod unload restores original predicate")
  local calls = e.calls
  f.tick()
  T.eq(e.calls, calls, "unloaded callback no longer runs")
  T.eq(Follower.current(f.world), nil, "unload removes companion through native update")
  T.eq(f.world.npcs[1], bystander, "unload preserves map objects")
  local failed = load(f, true)
  T.check(#failed.errors > 0, "failed entry is reported")
  T.eq(Follower.setShouldSpawn(nil), nativeDefault, "failed entry rolls back legacy setter")
  f.tick()
  T.eq(Follower.current(f.world), nil, "failed mod cannot leave a companion running")
  failed.release()
end

-- Installing a Gen2 predicate must not replace Yellow's native companion or
-- enable an optional GBA companion. Both remain under their existing owners.
for _, version in ipairs({ "red", "yellow", "firered" }) do
  local f = Fixture.new(".", "gen2", version, 2, "native")
  local calls = 0
  local previous = Follower.setShouldSpawn(function() calls = calls + 1; return true end)
  f.tick()
  T.eq(calls, 0, "Gen2 predicate is not called for " .. version)
  T.eq(f.current() ~= nil, version == "yellow", "other generation retains native follower default")
  Follower.setShouldSpawn(previous)
  f.close()
end
Version.set(oldVersion)
T.finish("native Gen2 follower setter lifecycle")
