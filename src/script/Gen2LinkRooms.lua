-- GOLD / SILVER / CRYSTAL: THE POKeMON CENTER 2F LINK RECEPTIONISTS
-- (docs/online-design.md 2.7, WS6a), through src/online/LinkRooms.lua.
--
-- The receptionist's own script (pret maps/Pokecenter2F.asm) is unchanged;
-- these are the specials it calls, answering through wScriptVar as the
-- cartridge's do:
--
--   SetBitsForLinkTradeRequest / ...BattleRequest / ...TimeCapsuleRequest
--                                which room was asked for
--   WaitForLinkedFriend          the link: LinkRooms.open(room, "connect")
--                                (HOST / JOIN by code); 1 = a friend is there
--   CheckLinkTimeout_Receptionist
--                                1 = still linked after the save; also fills
--                                the byte the next `readmem` reads
--                                (wOtherPlayerLinkMode: 0 = a Gen 1 game)
--   CheckBothSelectedSameRoom    1 = both asked for the same room
--   CableClubCheckWhichChris     1 = host (which seat sprite is the friend)
--   CloseLink                    drops the held link
--   TradeCenter / Colosseum / TimeCapsule
--                                the console in the room: the held session
--                                goes on into its trade or battle and stays
--                                up for another; a friend who has gone puts
--                                the player back on the 2F door, where the
--                                2F's "left the room" scene walks them out
--                                (the cartridge's MAPSETUP_LINKRETURN)
--
-- Everything the cartridge then says -- "please come again", "incompatible
-- rooms", "can't link to the past" -- is the script's own text.

local Commands = require("src.script.Commands")
local LinkRooms = require("src.online.LinkRooms")

local M = {}

M.SPECIALS = {
  SetBitsForLinkTradeRequest = "g2_link_request_trade",
  SetBitsForBattleRequest = "g2_link_request_battle",
  SetBitsForTimeCapsuleRequest = "g2_link_request_timecapsule",
  WaitForLinkedFriend = "g2_link_wait_friend",
  CheckLinkTimeout_Receptionist = "g2_link_timeout",
  Special_CheckLinkTimeout = "g2_link_timeout",
  CheckBothSelectedSameRoom = "g2_link_same_room",
  CableClubCheckWhichChris = "g2_link_which_chris",
  Special_CableClubCheckWhichChris = "g2_link_which_chris",
  CloseLink = "g2_link_close",
  TradeCenter = "g2_link_seat",
  Special_TradeCenter = "g2_link_seat",
  Colosseum = "g2_link_seat",
  Special_Colosseum = "g2_link_seat",
  TimeCapsule = "g2_link_seat",
  Special_TimeCapsule = "g2_link_seat",
}

local function answer(ctx, value)
  value = math.floor(value or 0) % 256
  ctx.g2Var = value
  ctx.lastCheck = value ~= 0
end

local function state(ctx)
  local game = ctx.game or {}
  game.g2LinkRoom = game.g2LinkRoom or {}
  return game.g2LinkRoom
end

local function request(room)
  return function(ctx) state(ctx).room = room end
end
Commands.g2_link_request_trade = request("trade")
Commands.g2_link_request_battle = request("battle")
Commands.g2_link_request_timecapsule = request("timecapsule")

function Commands.g2_link_wait_friend(ctx)
  local st = state(ctx)
  local ow = ctx.overworld
  st.returnMap = ow and ow.map and ow.map.id
  st.result = LinkRooms.await(ctx, function(done)
    -- the friend's seat sprite is the script's own (g2_link_which_chris)
    LinkRooms.open(ctx.game, st.room or "trade", { phase = "connect", noGhost = true }, done)
  end)
  answer(ctx, (st.result == "linked" or st.result == "mismatch") and 1 or 0)
end
Commands.meta = Commands.meta or {}
Commands.meta.g2_link_wait_friend = { foreground = true, blocking = true }

-- the `readmem <addr>` a few rows on: wOtherPlayerLinkMode, at the address
-- this cartridge uses (Gold $CE51, Crystal $CF51), read off the script
local function nextReadmem(ctx)
  local script, pc = ctx.script, ctx.pc
  if type(script) ~= "table" or not pc then return nil end
  for i = pc + 1, math.min(#script, pc + 4) do
    local row = script[i]
    if type(row) == "table" and row[1] == "g2_readmem" then return tonumber(row[2]) end
  end
  return nil
end

function Commands.g2_link_timeout(ctx)
  local st = state(ctx)
  local linked = st.result == "mismatch" or (st.result == "linked" and LinkRooms.pending() ~= nil)
  local last = LinkRooms.last or {}
  local addr = nextReadmem(ctx)
  if addr and ctx.save then
    ctx.save.g2Wram = ctx.save.g2Wram or {}
    -- nonzero: the friend's game is a Gen 2 one; 0 sends Trade Center and
    -- Colosseum to "can't link to the past" and the Time Capsule in
    local peerGen = tonumber(last.peerGen)
    ctx.save.g2Wram[addr] = (peerGen == 1) and 0 or 1
  end
  answer(ctx, linked and 1 or 0)
end

function Commands.g2_link_same_room(ctx)
  local st = state(ctx)
  local same = st.result == "linked" and LinkRooms.pending() ~= nil
  if not same then LinkRooms.close() end
  answer(ctx, same and 1 or 0)
end

function Commands.g2_link_which_chris(ctx)
  local last = LinkRooms.last
  answer(ctx, (last and last.isHost) and 1 or 0)
end

function Commands.g2_link_close(ctx)
  LinkRooms.close()
  state(ctx).result = nil
end

-- the 2F door that leads into the room the player is standing in
function M.returnCell(data, returnMap, roomMap)
  local def = data and data.maps and data.maps[returnMap]
  for _, w in ipairs(def and def.warps or {}) do
    if w.destMap == roomMap then return w.x, w.y end
  end
  return nil
end

function Commands.g2_link_seat(ctx)
  local st = state(ctx)
  local result = LinkRooms.await(ctx, function(done) LinkRooms.resume(ctx.game, done) end)
  st.seatResult = result
  if result == "nosession" then return end
  if LinkRooms.pending() then return end   -- still linked: the room goes on
  -- MAPSETUP_LINKRETURN: back to the 2F, on the door of this room
  local ow = ctx.overworld
  local room = ow and ow.map and ow.map.id
  local back = st.returnMap
  local data = ctx.game and ctx.game.data
  local x, y = M.returnCell(data, back, room)
  st.room, st.result = nil, nil
  if back and x and y and ctx.runner then
    Commands.warp(ctx, back, x, y, "down")
  end
end
Commands.meta.g2_link_seat = { foreground = true, blocking = true }

return M
