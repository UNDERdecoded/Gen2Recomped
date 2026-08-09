-- Driver: S.S. Anne kitchen PrintTrashText bins (#188).
-- Teleports beside each bin, interacts, screenshots the dialogue.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")

  local pass = true
  local function check(cond, msg)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end
  local function topIs(mt) return getmetatable(game.stack:top()) == mt end

  local bins = game.data.field.hiddenExtras
               and game.data.field.hiddenExtras.printTrash
               and game.data.field.hiddenExtras.printTrash.SS_ANNE_KITCHEN
  check(bins and #bins == 2, "SS_ANNE_KITCHEN has 2 PrintTrashText bins")

  for i, bin in ipairs(bins or {}) do
    -- stand west of the bin facing right (cooks occupy the column)
    U.teleport(game, "SS_ANNE_KITCHEN", bin.x - 1, bin.y, "right")
    local ow = game.overworld
    local fx, fy = ow.player:facingCell()
    U.log(("bin %d: at (%d,%d) facing %s -> (%d,%d)"):format(
          i, ow.player.cellX, ow.player.cellY, ow.player.facing, fx, fy))
    check(fx == bin.x and fy == bin.y, ("facing kitchen trash at (%d,%d)"):format(bin.x, bin.y))

    U.tap(game, "a")
    local opened = false
    for _ = 1, 60 do
      if topIs(TextBox) then opened = true; break end
      U.wait(2)
    end
    check(opened, ("bin %d opened a TextBox"):format(i))
    if opened then
      local box = game.stack:top()
      for _ = 1, 180 do
        if not topIs(TextBox) then break end
        if box.waiting or box.done then break end
        U.wait(1)
      end
      U.wait(4)
      local page = box.pages and box.pages[1]
      local body = type(page) == "table" and table.concat(page, "\n")
                  or (type(page) == "string" and page or "")
      U.log("dialogue:", body:gsub("\n", "\\n"):sub(1, 80))
      check(body:find("only trash here", 1, true) ~= nil,
            ("bin %d shows trash dialogue"):format(i))
      U.shot(game, DIR .. ("/ss_anne_kitchen_trash_%d.png"):format(i))
      for _ = 1, 40 do
        if not topIs(TextBox) then break end
        U.tap(game, "a")
        U.wait(2)
      end
    end
  end

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
end
