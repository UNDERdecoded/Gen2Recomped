-- Driver: gym-leader post-battle dialogue chain (#164).
-- Invokes checkVictoryRewards for Brock then Misty (same path as a win)
-- and screenshots pages that must include badge-effect + TM explanation
-- text -- not just a synthetic "received badge/TM" stub.
--
--   SHOT_DIR=/tmp/gym164 POKEPORT_DRIVER=tests/drivers/gym_leader_victory_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")
  local OW = require("src.world.OverworldController")

  local function currentPageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local page = top.pages and top.pages[top.pageIndex]
    if not page then return "" end
    return table.concat(page, "\n")
  end

  local function mashUntil(cond)
    for _ = 1, 1200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(2)
    end
    return false
  end

  local function advancePages(want, shotName)
    U.log(shotName, "waiting for:", want)
    local ok = mashUntil(function()
      local top = game.stack:top()
      if getmetatable(top) ~= TextBox then return false end
      -- only match once the current page has finished typing
      if not (top.waiting or top.done) then return false end
      return currentPageText():find(want, 1, true) ~= nil
    end)
    U.log(shotName, "found:", ok, "page:", currentPageText():gsub("\n", "\\n"))
    U.shot(game, DIR .. "/" .. shotName .. ".png")
    assert(ok, shotName .. " missing dialogue containing: " .. want)
  end

  local function runLeader(mapId, x, y, class, party, shots)
    while game.stack:top() do game.stack:pop() end
    game.save.flags = game.save.flags or {}
    game.save.inventory = game.save.inventory or {}
    game.save.defeatedTrainers = game.save.defeatedTrainers or {}
    game.stack:push(OW, mapId, x, y, "up")
    U.wait(5)
    local ow = game.stack:top()
    U.shot(game, DIR .. "/" .. shots.prefix .. "_0_gym.png")
    ow:checkVictoryRewards(class, party)
    U.wait(10)
    for _, s in ipairs(shots.pages) do
      advancePages(s.want, shots.prefix .. "_" .. s.name)
    end
    U.log(shots.prefix, "closing box:", mashUntil(function()
      return game.stack:top() == ow
    end))
    U.shot(game, DIR .. "/" .. shots.prefix .. "_done.png")
  end

  game.save.player.name = game.save.player.name or "RED"

  runLeader("PEWTER_GYM", 4, 3, "OPP_BROCK", 1, {
    prefix = "brock",
    pages = {
      { want = "BOULDERBADGE", name = "1_badge" },
      { want = "FLASH", name = "2_flash" },
      { want = "Wait!", name = "3_wait" },
      { want = "TM34", name = "4_tm34" },
      { want = "BIDE", name = "5_bide" },
    },
  })
  assert(game.save.flags.EVENT_BEAT_BROCK, "EVENT_BEAT_BROCK")
  assert(game.save.inventory.BOULDERBADGE, "BOULDERBADGE")
  assert((game.save.inventory.TM_BIDE or 0) >= 1, "TM_BIDE")

  runLeader("CERULEAN_GYM", 5, 5, "OPP_MISTY", 1, {
    prefix = "misty",
    pages = {
      { want = "CASCADEBADGE", name = "1_badge" },
      { want = "CUT", name = "2_cut" },
      { want = "TM11", name = "3_tm11" },
    },
  })
  assert(game.save.flags.EVENT_BEAT_MISTY, "EVENT_BEAT_MISTY")
  assert(game.save.inventory.CASCADEBADGE, "CASCADEBADGE")
  assert((game.save.inventory.TM_BUBBLEBEAM or 0) >= 1, "TM_BUBBLEBEAM")

  U.log("gym_leader_victory_test: ok")
end
