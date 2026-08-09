-- Driver: reproduce/verify #204 -- the PvP link/online battle crash when the
-- "level ruling" is left on ANY.
--
-- The link level picker cycles a string sentinel "ANY" meaning "use each
-- mon's real level" (Gen1's link cable always fought at the real level, so
-- ANY is the project's name for "no forced level"). LinkState.levelForWire is
-- supposed to turn that sentinel into nil before it goes on the wire; a broken
-- `x and nil or y` idiom instead let the literal "ANY" reach opts.forceLevel,
-- and Protocol.unpackMon then crashed on math.floor("ANY") the instant newHost
-- unpacked the parties (report traceback: Protocol.lua unpackMon <- LinkBattle
-- unpackParty <- newHost <- LinkState.update). This drives that exact host
-- battle path in a real window with the bad value forceLevel = "ANY".
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local Net = require("src.link.Net")
  local LinkBattle = require("src.link.LinkBattle")

  -- a low-level host mon and a high-level foe: the ANY ruling must keep both
  -- real levels (12 and 100), unlike an AUTO 50 ruling that forces them equal
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "RED"
  local foeParty = { Pokemon.new(game.data, "GEODUDE", 100) }

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(5)

  local netA = Net.loopbackPair() -- the guest end is unused: the intro is
                                  -- local, and the crash (if present) fires
                                  -- during newHost before any turn is taken
  local opts = {
    myParty = Protocol.packParty(game.save.party),
    theirParty = Protocol.packParty(foeParty),
    theirName = "BLUE",
    seed = 24680,
    forceLevel = "ANY", -- the exact value LinkState.levelForWire wrongly emitted
  }

  local ok, battle = pcall(LinkBattle.newHost, game, netA, opts)
  if not ok then
    -- pre-fix: math.floor("ANY") throws inside unpackMon; the battle never
    -- starts. Capture the still-in-overworld state and the error message
    -- (the harness would otherwise just print "driver error" and exit, with
    -- no on-screen error screen to shoot).
    U.log("LINK_ANY_204: newHost CRASHED (bug present): " .. tostring(battle))
    U.shot(game, DIR .. "/link_any_204_crash.png")
    U.log("LINK_ANY_204: done (crash reproduced)")
    return
  end

  -- post-fix: the battle constructs; push it and screenshot the intro/scene
  game.stack:push(battle)
  U.wait(20)
  U.shot(game, DIR .. "/link_any_204_battle_intro.png")
  U.wait(40)
  U.shot(game, DIR .. "/link_any_204_battle_scene.png")

  local hostLvl = battle.player and battle.player.mon and battle.player.mon.level
  local foeLvl = battle.enemy and battle.enemy.mon and battle.enemy.mon.level
  U.log(("LINK_ANY_204: battle started; host lvl=%s foe lvl=%s (expect 12 / 100)")
        :format(tostring(hostLvl), tostring(foeLvl)))
  if hostLvl == 12 and foeLvl == 100 then
    U.log("LINK_ANY_204: PASS -- real levels preserved under the ANY ruling")
  else
    U.log("LINK_ANY_204: FAIL -- levels not preserved (host=" ..
          tostring(hostLvl) .. " foe=" .. tostring(foeLvl) .. ")")
  end
  U.log("LINK_ANY_204: done")
end
