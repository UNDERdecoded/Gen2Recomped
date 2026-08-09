-- Driver (#222): a completed LAN link trade must autosave immediately, so a
-- player who quits before touching the START menu keeps the received mon and
-- cannot clone the sent one by resetting.
--
-- pokered engine/link/cable_club.asm: the Cable Club calls SaveSAVtoSRAM
-- (engine/menus/save.asm) right after every trade commits, so the swap is on
-- the cartridge the instant it happens.  Our LinkState:updateTrade "done"
-- branch swaps game.save.party in memory (TradeSession:apply) but, before the
-- fix, never persisted it -- SaveData.load then returned the pre-trade party
-- from disk, losing the received mon and re-materializing the sent one (the
-- classic reset-to-clone vector).
--
-- This drives the real receiver side: lay a baseline disk save with a PIDGEY
-- party (the "player saved earlier" state), negotiate a TradeSession to
-- "done" against a peer's RATTATA (RATTATA has no trade evolution, so the run
-- is deterministic), hand it to a live LinkState so the completion branch
-- runs, then RELOAD FROM DISK and assert the on-disk party holds the received
-- RATTATA and no stale PIDGEY -- fails while the autosave is missing, passes
-- once updateTrade calls game:writeSave().
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local LinkState = require("src.link.LinkState")
  local Net = require("src.link.Net")
  local SaveData = require("src.core.SaveData")
  local TextBox = require("src.render.TextBox")
  local TradeAnim = require("src.ui.TradeAnim")

  local function topIs(cls)
    return getmetatable(game.stack:top()) == cls
  end

  -- (1) a real overworld so writeSave's captureSave has a world to stamp
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(5)

  -- (2) baseline party + baseline disk save: this is the state the player
  -- would fall back to if the trade never persisted (must NOT contain RATTATA)
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 10) }
  local version = game.save.version
  game:writeSave()
  U.shot(game, DIR .. "/bug222_00_before.png")

  local baseline = SaveData.load(version)
  U.log("baseline on disk:", baseline and baseline.party and baseline.party[1]
        and baseline.party[1].species, "count:",
        baseline and baseline.party and #baseline.party)
  assert(baseline and baseline.party and baseline.party[1]
         and baseline.party[1].species == "PIDGEY",
    "#222 setup: baseline disk save must hold the PIDGEY party")

  -- (3) drive two TradeSessions to "done" exactly like run_link_tests.lua:
  -- ours is built on the LIVE game.save.party so apply() mutates it in place.
  local peerParty = { Pokemon.new(game.data, "RATTATA", 8) }
  peerParty[1].ot = "CULLEN"; peerParty[1].otId = 16012 -- distinct sender
  local ourTrade = Protocol.TradeSession.new(game.data, game.save.party)
  local peerTrade = Protocol.TradeSession.new(game.data, peerParty)
  ourTrade:handle({ type = "party", mons = Protocol.packParty(peerParty) })
  peerTrade:handle({ type = "party", mons = Protocol.packParty(game.save.party) })
  assert(ourTrade.stage == "picking", "trade should reach picking")
  local pickOurs = ourTrade:pick(1)   -- gives PIDGEY
  local pickPeer = peerTrade:pick(1)  -- gives RATTATA
  ourTrade:handle(pickPeer)
  peerTrade:handle(pickOurs)
  assert(ourTrade.stage == "confirming", "both picks -> confirming")
  local cOurs = ourTrade:confirm(true)
  local cPeer = peerTrade:confirm(true)
  ourTrade:handle(cPeer)
  peerTrade:handle(cOurs)
  assert(ourTrade.stage == "done", "both confirms -> done")

  -- (4) attach the completed session to a live LinkState in the trade stage,
  -- fresh Net (no peer) so poll() is empty and the "done" branch runs at once
  local ls = LinkState.new(game)
  ls.net = Net.new()
  ls.peerName = "CULLEN"
  ls.verdict = "full"
  ls.confirmed = true
  ls.stage = "trade"
  ls.trade = ourTrade
  game.stack:push(ls)

  -- (5) let the stack update ls once: the "done" branch applies the swap into
  -- game.save.party, autosaves (after the fix), pops ls, pushes TradeAnim
  for _ = 1, 120 do
    if game.stack:top() ~= ls then break end
    U.wait(1)
  end
  assert(game.stack:top() ~= ls, "#222: LinkState must leave the trade 'done' branch")
  U.log("in-memory party after trade:", game.save.party[1]
        and game.save.party[1].species)

  -- advance the TradeAnim until the "Trade completed!" TextBox appears for the
  -- after shot; the disk write already happened in the done branch, this is
  -- cosmetic.  A fresh Font require keeps this independent of TradeAnim state.
  local Font = require("src.render.Font")
  local sawText = false
  for _ = 1, 4000 do
    local top = game.stack:top()
    if top == game.overworld then break end
    if getmetatable(top) == TradeAnim and not top.waitingText then
      top:update(1 / 60)
    end
    if topIs(TextBox) then sawText = true; break end
    U.tap(game, "a")
    U.wait(1)
  end
  -- fully reveal the current page ("Trade completed!") so the shot shows text
  -- regardless of the typewriter speed (mirrors trade_anim_test.lua)
  local tb = game.stack:top()
  if getmetatable(tb) == TextBox and tb.pages and tb.pageIndex then
    local page = tb.pages[tb.pageIndex]
    if page then
      tb.shown = {}
      for _, line in ipairs(page) do
        tb.shown[#tb.shown + 1] = Font.encode(line)
      end
      tb.lineIndex = #page
      tb.charIndex = #(tb.shown[#tb.shown] or {})
      tb.done = true
    end
  end
  U.wait(2)
  U.shot(game, DIR .. "/bug222_01_trade_complete.png")
  U.log("reached trade-complete text:", sawText)

  -- (6) RELOAD FROM DISK and assert the trade was persisted without a manual
  -- save.  These fail before the fix (disk still holds the baseline PIDGEY).
  local disk = SaveData.load(version)
  U.log("on disk after trade:", disk and disk.party and disk.party[1]
        and disk.party[1].species, "count:",
        disk and disk.party and #disk.party)

  assert(disk and disk.party, "#222: a save file must exist on disk")
  assert(disk.party[1] and disk.party[1].species == "RATTATA",
    "#222: trade must autosave -- on-disk lead must be the received RATTATA, was "
      .. tostring(disk.party[1] and disk.party[1].species))
  assert(#disk.party == 1,
    "#222: on-disk party must be exactly the swapped party (no phantom slot), had "
      .. tostring(#disk.party))
  for i, mon in ipairs(disk.party) do
    assert(mon.species ~= "PIDGEY",
      "#222: the sent PIDGEY must not survive on disk (clone vector), found at slot "
        .. tostring(i))
  end

  U.log("#222 PASS: link trade autosaved; disk holds RATTATA, PIDGEY gone")
end
