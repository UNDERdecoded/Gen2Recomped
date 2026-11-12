-- NEW GAME -> RUN SETUP -> the game's own new-game start.
--
-- Every family's NEW GAME goes through here (Game:makeTitleState for the
-- Game Boy / GBA titles, the DS main menus for Platinum, HGSS and B/W):
-- the RunSetup screen asks whether this is a Nuzlocke run (plus Soul Link
-- and the randomizer), parks the answer in RunModes.pending, and `start`
-- builds the save -- SaveData.newGame / the DS fresh-save builders consume
-- the pending choice.  B goes back to where NEW GAME was chosen.
--
-- POKEPORT_RUNMODES=skip (headless harnesses that script the title screen
-- by button presses) starts straight away with every mode off.  Scripted
-- runs (POKEPORT_DRIVER / POKEPORT_AUTOPILOT) skip it too -- their NEW GAME
-- mashes A, which here would toggle a row forever -- unless
-- POKEPORT_RUNMODES=show asks for the screen.

local RunModes = require("src.runmodes.RunModes")

local Gate = {}

function Gate.skip(game)
  local env = os.getenv and os.getenv("POKEPORT_RUNMODES")
  if env == "skip" or env == "off" then return true end
  if env ~= "show" and os.getenv and (os.getenv("POKEPORT_DRIVER") or os.getenv("POKEPORT_AUTOPILOT")) then
    return true
  end
  if not (game and game.stack and game.stack.push) then return true end
  return false
end

-- run `start()` after the player has chosen; `cancel()` (optional) on B
function Gate.run(game, start, cancel)
  RunModes.setPending(nil)
  if Gate.skip(game) then return start() end
  local ok, RunSetup = pcall(require, "src.ui.RunSetup")
  if not ok then
    require("src.core.Logger").warn("run setup unavailable: %s", tostring(RunSetup))
    return start()
  end
  RunSetup.open(game, {
    onDone = function(choice)
      RunModes.setPending(choice)
      start()
      -- a family whose start did not build its save through a consumer
      -- (nothing took the pending choice) applies it to whatever save is live
      if RunModes.pending and game.save then RunModes.consumePending(game.save) end
    end,
    onCancel = function()
      RunModes.setPending(nil)
      if cancel then cancel() end
    end,
  })
end

return Gate
