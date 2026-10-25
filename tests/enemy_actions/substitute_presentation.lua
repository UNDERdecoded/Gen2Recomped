-- Owned controller inputs execute the real sequencer/VM and host battle queue.
-- No draw or graphics application is launched; every controller tick is kept.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local rows = {}
  local Anim, Seq, Runtime, Presentation
  if native then
    Anim = require("src.core.game3.battle.anim")
    Seq = require("src.core.game3.battle.anim_seq")
    Runtime = require("src.core.game3.runtime")
    local moves = require("src.core.game3.battle.moves")
    for _, n in ipairs({ 144, 164 }) do
      local def = {}
      for k, v in pairs(moves._rom[33]) do
        def[k] = v
      end
      moves._rom[n] = def
      f.data.gen3Moves._rom[n] = def
      local name = n == 144 and "TRANSFORM" or "SUBSTITUTE"
      f.data.gen3Pokemon._moveNames[n] = name
      moves.BY_NUM[n], moves._numByName[name] = name, n
    end
    local function swap(arg)
      return {
        { op = "createvisualtask", task = "SwapMonSpriteToFromSubstitute", priority = 2, args = { arg } },
        { op = "end" },
      }
    end
    -- Both qualified version-5 imports use these two decoded special programs.
    -- Keep the name table contiguous, as required by the native pack lookup.
    local names = {}
    for i = 0, 4 do
      names[i] = "UNUSED_" .. i
    end
    names[5], names[6] = "SUBSTITUTE_TO_MON", "MON_TO_SUBSTITUTE"
    Anim.loadPack({
      version = 5,
      special = { [5] = swap(1), [6] = swap(0) },
      specialNames = names,
      tags = {},
      moves = {
        [33] = { { op = "delay", frames = 200 }, { op = "end" } },
        [144] = { { op = "delay", frames = 200 }, { op = "end" } },
        [164] = { { op = "delay", frames = 200 }, { op = "end" } },
      },
    })
  else
    Presentation = require("src.battle.Gen3SubstitutePresentation")
    f.data.constants.gen3BattlerCoords = {
      singles = { { x = 72, y = 80 }, { x = 176, y = 40 } },
      doubles = { { x = 32, y = 80 }, { x = 200, y = 40 }, { x = 90, y = 88 }, { x = 152, y = 32 } },
    }
    for _, n in ipairs({ 144, 164 }) do
      f.data.moves[("MOVE_%03d"):format(n)] = { index = n }
    end
  end
  for _, double in ipairs({ false, true }) do
    for id = 0, double and 3 or 1 do
      for _, scene in ipairs({ false, true }) do
        for _, move in ipairs({ 33, 144, 164 }) do
          for _, kind in ipairs({ "lower", "not-substitute", "restore", "broken-restore", "no-lower-restore" }) do
            local b = f.field(double)
            local user = f.actor(id)
            local lower = kind == "lower" or kind == "not-substitute"
            local visible = lower and kind ~= "not-substitute"
            local wasLowered = kind == "restore" or kind == "broken-restore"
            local hp = (kind == "broken-restore" or kind == "not-substitute") and 0 or 100
            -- The preceding Substitute animation creates its visible doll.
            -- Both controller inputs begin with that same prepared display.
            if not lower and move == 164 and scene and hp > 0 then
              visible = true
            end
            user.substituteHP = hp > 0 and hp or nil
            local name = lower and "SUBSTITUTE_TO_MON" or "MON_TO_SUBSTITUTE"
            local reached, commandIndex = false, 1
            if native then
              require("src.core.game3.battle")._st = b
              Runtime.session = { version = version, options = { battleScene = scene and 0 or 1 } }
              Anim.reset({ headless = false, double = double })
              Anim.setSubstitute(id, visible)
              local events = {
                { kind = "anim", anim = "special", name = name, attackerId = id, targetId = id },
                {
                  kind = "move",
                  moveId = move,
                  attackerId = id,
                  targetId = id % 2 == 0 and id + 1 or id - 1,
                },
              }
              if not lower then
                -- Native buildSteps associates restoration with the preceding
                -- move. Execute that preparation normally, then observe every
                -- tick of the restoration command from its actual launch.
                table.insert(events, 1, {
                  kind = "move",
                  moveId = move,
                  attackerId = id,
                  targetId = id % 2 == 0 and id + 1 or id - 1,
                })
                commandIndex = 2
              end
              Seq.beginEvents(events, function() end)
              Seq._subLowered[id] = wasLowered or nil
              if not lower then
                for preparation = 0, 250 do
                  if preparation > 0 then
                    Anim.update(1 / 60)
                  end
                  if not Anim.busy() then
                    Seq.update()
                  end
                  if Seq._i >= commandIndex and Seq._waitFrames == 0 then
                    break
                  end
                end
                assert(
                  Seq._i >= commandIndex and Seq._waitFrames == 0,
                  "restoration preparation did not complete"
                )
              end
            else
              f.game.save.options.animations = scene
              b.queue = {
                {
                  anim = name,
                  gbaSubstituteSpecial = true,
                  gbaSubstituteMove = ("MOVE_%03d"):format(move),
                  attackerPosition = id,
                  attackerIsPlayer = user.isPlayer,
                },
                {
                  fn = function()
                    reached = true
                  end,
                },
              }
              b.current, b.waitFrames, b.nextInsert = nil, nil, 0
              b._gbaSubstituteTransition = nil
              b._gbaSubstitutePresentation =
                { [user] = { substitute = visible, lowered = wasLowered, x = 0 } }
            end
            local frames, done = {}, false
            for tick = 0, 200 do
              local showing, offset
              if native then
                if tick > 0 then
                  Anim.update(1 / 60)
                end
                if not Anim.busy() then
                  Seq.update()
                end
                done = Seq._i > commandIndex
                local state = Anim.present(id)
                showing, offset = state.substitute, state.ox or 0
              else
                b:updateQueue()
                done = reached
                showing, offset = Presentation.showing(b, user), Presentation.offset(b, user)
              end
              frames[#frames + 1] = {
                tick = tick,
                substitute = showing,
                offset = offset,
                done = done,
                substituteHP = user.substituteHP or 0,
              }
              if done then
                break
              end
            end
            assert(done, "Substitute controller did not complete")
            rows[#rows + 1] =
              { double = double, actor = id, scene = scene, move = move, case = kind, frames = frames }
          end
        end
      end
    end
  end
  f.close()
  return rows
end
return M
