package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Fixture = dofile("tests/world_talk/fixture.lua")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    dofile("tests/world_talk/cases.lua").run(f)
    local probe = f.public.hooks:wrap("world.talk", function(next, ...)
      f.exports.seen.calls = f.exports.seen.calls + 1
      return next(...)
    end)
    -- Preserve the engine's existing guards before the public seam.
    for _, guard in ipairs({ "moving", "hidden", "gen5Blocker" }) do
      local polls, calls = f.exports.seen.calls, #f.calls
      f.patch(f.world.map, "signAtCell", function()
        return nil
      end)
      f.patch(f.world, "tryPcTile", function()
        return true
      end)
      if guard == "gen5Blocker" then
        f.npc.def.gen5Blocker = true
      else
        f.npc[guard] = true
      end
      f.interact()
      T.eq(f.exports.seen.calls, polls, guard .. " never queries talk hook")
      T.eq(#f.calls, calls, guard .. " never reaches native talk")
      f.npc[guard], f.npc.def.gen5Blocker = false, nil
    end
    if f.gen == 3 then
      f.world.player.elevation, f.npc.elevation = 1, 2
      local polls, calls = f.exports.seen.calls, #f.calls
      f.interact()
      T.eq(f.exports.seen.calls, polls, "GBA wrong elevation never talks")
      T.eq(#f.calls, calls, "GBA wrong elevation keeps native guard")
    end
    for _, follower in ipairs({
      { "pikachuFollower", "src.world.PikachuFollower" },
      { "hgssFollowMon", "src.world.HgssFollowMon" },
    }) do
      local called, polls = 0, f.exports.seen.calls
      f.patch(require(follower[2]), "talk", function()
        called = called + 1
      end)
      f.npc[follower[1]] = true
      f.world.player.elevation, f.npc.elevation = nil, nil
      f.interact()
      T.eq(called, 1, "special follower keeps native dispatch")
      T.eq(f.exports.seen.calls, polls, "special follower bypasses general NPC hook")
      f.npc[follower[1]] = nil
    end
    probe()
    local returned
    f.patch(f.world, "talkTo", function()
      return "native private result"
    end)
    local capture = f.public.hooks:wrap("world.talk", function(next)
      returned = next()
      return returned
    end)
    f.interact()
    T.eq(returned, nil, "default continuation matches Gen1's void talk contract")
    capture()
    -- Original talk failures propagate without being retried as a mod error.
    f.world.player.elevation, f.npc.elevation = nil, nil
    local failures = 0
    f.patch(f.world, "talkTo", function()
      failures = failures + 1
      error("native talk failure")
    end)
    local off = f.public.hooks:wrap("world.talk", function(next)
      return next()
    end)
    local ok, why = pcall(f.interact)
    T.eq(ok, false, "native failure propagates")
    T.check(tostring(why):find("native talk failure", 1, true) ~= nil, "native failure retained")
    T.eq(failures, 1, "native failure is never replayed")
    off()
    f.close()
  end
end
Version.set(originalVersion)
T.finish("world.talk native routing")
