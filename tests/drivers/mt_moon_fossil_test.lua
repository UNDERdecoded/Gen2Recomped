-- Driver: Mt Moon B2F fossil pick (scripts/MtMoonB2F.asm).  After the
-- Super Nerd is beaten, take one fossil and confirm he walks to the other
-- and says "All right. Then this is mine!" before it vanishes.
-- Runs DOME then HELIX paths (map is reset between).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")

  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "PIKACHU", 20))
  end

  local function runPick(tag, x, y, takeName, leaveName, itemId, expectNerdX, expectNerdY, gotFlag)
    game.save.flags = game.save.flags or {}
    game.save.flags.EVENT_BEAT_MT_MOON_3_SUPER_NERD = true
    game.save.flags.EVENT_GOT_DOME_FOSSIL = nil
    game.save.flags.EVENT_GOT_HELIX_FOSSIL = nil
    game.save.inventory.DOME_FOSSIL = nil
    game.save.inventory.HELIX_FOSSIL = nil
    game.save.objectToggles = game.save.objectToggles or {}
    game.save.objectToggles.MT_MOON_B2F = nil

    U.teleport(game, "MT_MOON_B2F", x, y, "up")
    local ow = game.overworld
    U.wait(5)

    local function idle()
      return game.stack:top() == ow and not ow.runner:isRunning()
             and #ow.scriptMoves == 0
    end
    local function mash(cond, label, cap)
      for _ = 1, cap or 400 do
        if cond() then return true end
        U.tap(game, "a")
        U.wait(3)
      end
      U.log("TIMEOUT:", tag, label)
      return false
    end
    local function fossilVisible(name)
      for _, n in ipairs(ow.npcs) do
        if n.def and n.def.name == name then return true end
      end
      return false
    end
    local function nerd()
      return ow:npcByIndex(1)
    end

    U.shot(game, DIR .. ("/mtmoon_%s_0_before.png"):format(tag))
    U.log(tag, "before", takeName .. ":", tostring(fossilVisible(takeName)),
          leaveName .. ":", tostring(fossilVisible(leaveName)),
          "nerd:", nerd() and (nerd().cellX .. "," .. nerd().cellY) or "nil")

    U.tap(game, "a")
    U.wait(24)
    U.shot(game, DIR .. ("/mtmoon_%s_1_ask.png"):format(tag))
    U.tap(game, "a") -- YES
    mash(function()
      return game.stack:top() == ow or ow.runner:isRunning()
    end, "received / walk start", 200)

    local sawMineText, midwalk = false, false
    for _ = 1, 500 do
      local n = nerd()
      if not midwalk and n and (n.cellX ~= 12 or n.cellY ~= 8
                               or n.moving or #ow.scriptMoves > 0) then
        if n.cellX ~= 12 or n.cellY ~= 8 or n.moving then
          midwalk = true
          U.shot(game, DIR .. ("/mtmoon_%s_2_walk.png"):format(tag))
        end
      end
      local top = game.stack:top()
      if top and top ~= ow and top.pages and top.done then
        local flat = ""
        for _, page in ipairs(top.pages) do
          for _, line in ipairs(page) do flat = flat .. line .. " " end
        end
        if flat:find("this is mine", 1, true) then
          sawMineText = true
          U.shot(game, DIR .. ("/mtmoon_%s_3_mine.png"):format(tag))
          break
        end
      end
      U.wait(1)
    end

    mash(idle, "cutscene idle", 400)
    U.shot(game, DIR .. ("/mtmoon_%s_4_done.png"):format(tag))

    local n = nerd()
    U.log(tag, "sawMineText:", tostring(sawMineText),
          "midwalk:", tostring(midwalk))
    U.log(tag, "after", takeName .. ":", tostring(fossilVisible(takeName)),
          leaveName .. ":", tostring(fossilVisible(leaveName)))
    U.log(tag, "nerd at:", n and (n.cellX .. "," .. n.cellY) or "nil",
          "expect:", expectNerdX .. "," .. expectNerdY)
    U.log(tag, "flag:", gotFlag, tostring(game.save.flags[gotFlag]),
          "bag:", tostring(game.save.inventory[itemId]))
  end

  runPick("dome", 12, 7,
          "MTMOONB2F_DOME_FOSSIL", "MTMOONB2F_HELIX_FOSSIL", "DOME_FOSSIL",
          13, 7, "EVENT_GOT_DOME_FOSSIL")
  runPick("helix", 13, 7,
          "MTMOONB2F_HELIX_FOSSIL", "MTMOONB2F_DOME_FOSSIL", "HELIX_FOSSIL",
          12, 7, "EVENT_GOT_HELIX_FOSSIL")

  U.log("DONE")
  love.event.quit()
end
