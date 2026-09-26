-- FireRed League progression regression.
--
-- The only setup jump places a fresh test save in the Indigo Plateau lobby.
-- From there the driver enters Lorelei through the real lobby warp, defeats
-- every Elite Four member and the Champion through normal interaction, walks
-- through each opened exit, and finishes by reaching the Hall of Fame.
return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  game.writeSave = function() return false end
  local save = U.freshSave(game)
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = {
    { id = "PSYCHIC", pp = 99, maxPp = 99 },
    { id = "ICE_BEAM", pp = 99, maxPp = 99 },
    { id = "THUNDERBOLT", pp = 99, maxPp = 99 },
    { id = "RECOVER", pp = 99, maxPp = 99 },
  }
  mon.hp, mon.maxHp = 322, 322
  save.party = { mon }

  local function stable()
    local ow = game.overworld
    return ow and game.stack:top() == ow and not ow.runner:isRunning()
  end

  local function waitStable(maxFrames)
    for _ = 1, maxFrames or 1600 do
      local ow = game.overworld
      if ow and game.stack:top() == ow and not ow.runner:isRunning()
         and #ow.scriptMoves == 0 and not ow.player.moving then
        U.wait(10)
        return
      end
      U.wait(1)
    end
    error("overworld did not become stable")
  end

  local function mashBattle(flag, label, maxFrames)
    for frame = 1, maxFrames or 18000 do
      if frame % 8 == 1 then U.tap(game, "a") else U.wait(1) end
      if save.flags[flag] and stable() then
        U.wait(20)
        U.log("DEFEATED", label, "map", game.overworld.map.id,
          "at", game.overworld.player.cellX, game.overworld.player.cellY)
        return
      end
    end
    error(label .. " battle did not complete")
  end

  local function walkUntilMap(target, dir, maxFrames)
    for _ = 1, maxFrames or 800 do
      if game.overworld and game.overworld.map.id == target then
        game.input.state[dir] = false
        U.wait(20)
        U.log("ENTERED", target, "at", game.overworld.player.cellX,
          game.overworld.player.cellY)
        return
      end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
    end
    game.input.state[dir] = false
    error("did not reach " .. target .. " by walking " .. dir)
  end

  local function walkTo(x, y, maxFrames)
    local map = game.overworld.map.id
    for _ = 1, maxFrames or 1200 do
      local p = game.overworld.player
      if game.overworld.map.id ~= map then
        error("left " .. map .. " while walking to cell")
      end
      if p.cellX == x and p.cellY == y then
        game.input.state.up = false
        game.input.state.down = false
        game.input.state.left = false
        game.input.state.right = false
        U.wait(10)
        return
      end
      local dir
      if p.cellX < x then dir = "right"
      elseif p.cellX > x then dir = "left"
      elseif p.cellY < y then dir = "down"
      else dir = "up" end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
      game.input.state[dir] = false
    end
    local p = game.overworld.player
    error(("could not walk to (%d,%d), stopped at (%d,%d)"):format(
      x, y, p.cellX, p.cellY))
  end

  local function settleSimpleEntry(label)
    U.wait(80)
    local p = game.overworld.player
    assert(p.cellX == 6 and p.cellY == 7,
      label .. " normal entry walk did not reach (6,7)")
  end

  local function fightSimpleMember(flag, nativeFlag, label, nextMap)
    walkTo(6, 6)
    game.overworld.player.facing = "up"
    mashBattle(flag, label)
    assert(save.flags[nativeFlag], label .. " native FireRed defeat flag missing")
    -- The member remains at (6,5); walk around them to the opened exit.
    walkTo(5, 6)
    walkTo(5, 3)
    walkTo(6, 3)
    walkUntilMap(nextMap, "up")
  end

  U.teleport(game, "MAP_G13_N00", 4, 2, "up")
  walkUntilMap("LORELEIS_ROOM", "up")
  settleSimpleEntry("Lorelei")
  fightSimpleMember("EVENT_BEAT_LORELEIS_ROOM_TRAINER_0", "FLAG_G3_04B8",
    "Lorelei", "BRUNOS_ROOM")

  settleSimpleEntry("Bruno")
  fightSimpleMember("EVENT_BEAT_BRUNOS_ROOM_TRAINER_0", "FLAG_G3_04B9",
    "Bruno", "AGATHAS_ROOM")

  settleSimpleEntry("Agatha")
  fightSimpleMember("EVENT_BEAT_AGATHAS_ROOM_TRAINER_0", "FLAG_G3_04BA",
    "Agatha", "LANCES_ROOM")

  -- FireRed walks the player from Agatha's warp at (23,13) through Lance's
  -- corridor and stops at (6,10), immediately south of his approach lane.
  waitStable(1200)
  assert(game.overworld.player.cellX == 6 and game.overworld.player.cellY == 10,
    "Lance room normal entry walk did not reach (6,10)")
  walkTo(6, 9)
  game.overworld.player.facing = "up"
  mashBattle("EVENT_BEAT_LANCE", "Lance")
  assert(save.flags.FLAG_G3_04BB, "Lance native FireRed defeat flag missing")
  walkTo(5, 9)
  walkTo(5, 6)
  walkTo(6, 6)
  walkUntilMap("CHAMPIONS_ROOM", "up", 1200)

  -- FireRed's Champion room is a forced entry scene. Let that scene walk the
  -- player to the rival, run the battle and Oak sequence, then require the
  -- normal warp into the Hall of Fame.
  local championWon, enteredHall = false, false
  for frame = 1, 26000 do
    if frame % 8 == 1 then U.tap(game, "a") else U.wait(1) end
    if not championWon and save.flags.FLAG_G3_04BC then
      championWon = true
      assert(save.flags.EVENT_BEAT_CHAMPION_RIVAL,
        "Champion legacy completion flag missing")
      assert(save.flags.EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN,
        "Champion run-scoped completion flag missing")
      U.log("DEFEATED Champion", "map", game.overworld.map.id,
        "at", game.overworld.player.cellX, game.overworld.player.cellY)
    end
    if championWon and not enteredHall and game.overworld
       and game.overworld.map.id == "HALL_OF_FAME" then
      enteredHall = true
      U.log("ENTERED Hall of Fame")
    end
    if enteredHall and save.flags.FLAG_G3_082C
       and (tonumber(save.hallOfFame) or 0) >= 1 then
      U.log("PASS continuous Lorelei -> Bruno -> Agatha -> Lance -> Champion -> Hall of Fame induction")
      love.event.quit(0)
      return
    end
  end
  error(championWon and "Champion did not complete the Hall of Fame induction"
    or "Champion battle did not complete")
end
