-- Driver (#215): a link-traded mon must keep its ORIGINAL trainer's OT
-- name and ID on the receiving game, not adopt the receiver's identity.
--
-- pokered engine/link/cable_club.asm + home/serial.asm: a trade transmits
-- the whole party data block, which carries each mon's OT ID (party_struct
-- MON_OTID offset) and the OT-names block (wPartyMonOT).  The receiving game
-- copies both verbatim and never overwrites -- a differing OT/ID is exactly
-- what marks a mon as traded (boosted EXP, high-level disobedience).
--
-- The bug: Protocol.packMon/unpackMon dropped mon.ot/mon.otId on the wire,
-- so a received mon arrived ot=nil/otId=nil and SummaryMenu (status_screen.asm
-- StatusScreen) fell back to the local player's name/ID -- the reporter saw
-- the sender's CULLEN/16012 mon show up on the receiver as RED/60368.  This
-- drives the receiver side headlessly: pack a CULLEN-owned mon and unpack it,
-- then read exactly what SummaryMenu draws in the IDNo/OT slots.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local SummaryMenu = require("src.ui.SummaryMenu")
  local BattleState = require("src.battle.BattleState")
  local Font = require("src.render.Font")

  -- This install is the RECEIVER: player RED, ID 60368 (from the report's
  -- Blue window).  A correctly preserved OT must NOT match these.
  game.save.player.name = "RED"
  game.save.player.id = 60368

  -- Capture exactly the strings SummaryMenu draws in the IDNo value slot
  -- (x=96, y=112) and the OT value slot (x=96, y=128) on page 1.  Monkeypatch
  -- the Font table field so SummaryMenu's own `local Font` reference resolves
  -- to our wrapper at call time -- this reads the real rendered strings, not
  -- Protocol in isolation, so it fails while the received mon carries no OT.
  local realDraw = Font.draw
  local function recordShot(mon, path)
    local summary = SummaryMenu.new(game, mon)
    game.stack:push(summary)
    U.wait(4)
    local capturedId, capturedOt = nil, nil
    Font.draw = function(text, x, y)
      if x == 96 and y == 112 then capturedId = text end
      if x == 96 and y == 128 then capturedOt = text end
      return realDraw(text, x, y)
    end
    U.shot(game, path)
    Font.draw = realDraw
    game.stack:pop()
    U.wait(2)
    return capturedId, capturedOt
  end

  -- The bug case: a RATTATA caught by trainer CULLEN (id 16012), sent across
  -- the wire.  pack -> unpack is exactly what the trade session does to the
  -- mon before it lands in the receiver's party (Protocol.TradeSession).
  local sender = Pokemon.new(game.data, "RATTATA", 8)
  sender.ot = "CULLEN"
  sender.otId = 16012
  local received = Protocol.unpackMon(game.data, Protocol.packMon(sender))
  local recvId, recvOt =
    recordShot(received, DIR .. "/trade_ot_215_received_p1.png")
  U.log("received mon: IDNo=", tostring(recvId), " OT=", tostring(recvOt))

  -- Control: a mon caught locally on THIS game gets the player stamped as OT
  -- (BattleState.stampOT, engine/battle/core.asm on catch), so its summary
  -- correctly reads RED / 60368.  This proves the player-fallback path itself
  -- is fine and it is only the received mon that was wrong.
  local mine = Pokemon.new(game.data, "PIDGEY", 8)
  BattleState.stampOT(game.save, mine)
  local mineId, mineOt =
    recordShot(mine, DIR .. "/trade_ot_215_control_p1.png")
  U.log("self-caught mon: IDNo=", tostring(mineId), " OT=", tostring(mineOt))

  U.log("shots under", DIR)

  -- The received mon must show the ORIGINAL trainer, not the receiver.
  assert(recvOt == "CULLEN",
    "#215: received mon OT must render CULLEN (the original trainer), drew "
      .. tostring(recvOt))
  assert(recvId == "16012",
    "#215: received mon IDNo must render 16012 (the original trainer ID), drew "
      .. tostring(recvId))
  assert(recvOt ~= game.save.player.name,
    "#215: received mon must not adopt the receiver's OT name")
  assert(recvId ~= ("%05d"):format(game.save.player.id),
    "#215: received mon must not adopt the receiver's ID")

  -- Control must still show the local player (self-caught mon is unaffected).
  assert(mineOt == "RED",
    "control: self-caught mon OT must render RED, drew " .. tostring(mineOt))
  assert(mineId == "60368",
    "control: self-caught mon IDNo must render 60368, drew " .. tostring(mineId))

  U.log("#215 PASS: link-traded mon keeps the original trainer's OT/ID")
end
