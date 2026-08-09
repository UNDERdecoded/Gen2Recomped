-- Driver: NPC in-game trade cable animation (InternalClockTradeAnim).
-- Vermilion Trade House: SPEAROW -> FARFETCH'D (DUX).
--
--   SHOT_DIR=/tmp/trade_shots POKEPORT_DRIVER=tests/drivers/trade_anim_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/trade_shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local TradeAnim = require("src.ui.TradeAnim")
  local TextBox = require("src.render.TextBox")
  local PartyMenu = require("src.ui.PartyMenu")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local function topIs(cls)
    return getmetatable(game.stack:top()) == cls
  end

  game.save.party = { Pokemon.new(game.data, "SPEAROW", 10) }
  U.teleport(game, "VERMILION_TRADE_HOUSE", 3, 6, "up")
  U.wait(5)
  U.shot(game, DIR .. "/trade_00_house.png")

  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 200 do
    if topIs(ChoiceBox) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  U.shot(game, DIR .. "/trade_01_offer.png")
  U.tap(game, "a") -- YES
  U.wait(6)

  for _ = 1, 60 do
    if topIs(PartyMenu) then break end
    U.wait(1)
  end
  U.log("party menu:", topIs(PartyMenu))
  U.shot(game, DIR .. "/trade_02_party.png")
  U.tap(game, "a")
  U.wait(6)

  for _ = 1, 200 do
    if topIs(TradeAnim) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  local anim = game.stack:top()
  if getmetatable(anim) ~= TradeAnim then
    U.log("FAIL: TradeAnim never appeared")
    return
  end
  U.log("TradeAnim phase:", anim.phase)

  local function ffUntil(phase, cap)
    for _ = 1, cap or 3000 do
      if anim.phase == phase or anim.phase == "done" then break end
      if anim.waitingText or topIs(TextBox) then
        U.wait(1)
      else
        anim:update(1 / 60)
      end
    end
    U.wait(1)
  end

  -- hold mid show_player (scx settled, mon visible)
  ffUntil("show_player", 1)
  while anim.phase == "show_player" and (anim.sub ~= "hold" or anim.scx > 0) do
    anim:update(1 / 60)
  end
  for _ = 1, 10 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_03_show_player.png")
  U.log("show_player sub=", anim.sub, "scx=", anim.scx)

  ffUntil("open_cable", 500)
  -- mid scroll-in
  while anim.phase == "open_cable" and anim.scx > 40 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/trade_04_open_cable.png")
  U.log("open_cable scx=", anim.scx)

  ffUntil("ball_enter", 200)
  while anim.phase == "ball_enter" and anim.ballX < 0x80 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/trade_05_ball_enter.png")
  U.log("ball at", anim.ballX, anim.ballY)

  ffUntil("transfer_lr", 400)
  for _ = 1, 24 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_06_transfer_lr.png")

  ffUntil("went_to", 800)
  for _ = 1, 600 do
    if topIs(TextBox) then
      local tb = game.stack:top()
      if tb.done then break end
      -- finish typewriter so both lines are visible
      if tb.codes then tb.charIndex = #tb.codes end
      if tb.pages and tb.pageIndex and tb.lineIndex then
        local page = tb.pages[tb.pageIndex]
        if page and tb.lineIndex < #page then
          tb.lineIndex = #page
          tb.shown = {}
          for _, line in ipairs(page) do
            local codes = require("src.render.Font").encode(line)
            tb.shown[#tb.shown + 1] = codes
          end
          tb.charIndex = #(tb.shown[#tb.shown] or {})
          tb.done = true
        end
      end
      break
    end
    U.wait(1)
  end
  U.wait(2)
  U.shot(game, DIR .. "/trade_07_went_to.png")
  U.log("went-to:", topIs(TextBox))

  ffUntil("transfer_rl", 2500)
  for _ = 1, 16 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_08_transfer_rl.png")

  ffUntil("show_enemy", 800)
  while anim.phase == "show_enemy" and not anim.monVisible do
    anim:update(1 / 60)
  end
  for _ = 1, 30 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_09_show_enemy.png")

  for _ = 1, 5000 do
    if game.stack:top() == game.overworld then break end
    local top = game.stack:top()
    if getmetatable(top) == TradeAnim and not top.waitingText then
      top:update(1 / 60)
    end
    U.tap(game, "a")
    U.wait(1)
  end
  U.shot(game, DIR .. "/trade_10_done.png")
  local mon = game.save.party[1]
  U.log("party:", mon and mon.species, "nick:", mon and mon.nickname,
        "ot:", mon and mon.ot)
  U.log("done")
end
