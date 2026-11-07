-- RUBY / SAPPHIRE / EMERALD / FIRERED / LEAFGREEN: THE CABLE CLUB
-- (docs/online-design.md 2.7, WS6a), through src/online/LinkRooms.lua.
--
-- The cable club's scripts (data/scripts/cable_club.inc) are the cartridge's;
-- these are the specials they wait on, answering VAR_RESULT with the
-- cartridge's own LINKUP_* codes so every abort keeps its own line:
--
--   28 TryBattleLinkup    the link, room "battle" or "battle2" (VAR_0x8004
--                         single / double: the host's rules picker starts on
--                         that format); a multi answers
--                         LINKUP_WRONG_NUM_PLAYERS: two games only
--   29 TryTradeLinkup     the link, room "trade"
--        LINKUP_SUCCESS (1)          connected, both asked for this room
--        LINKUP_DIFF_SELECTIONS (3)  connected, the friend asked for another
--        LINKUP_FAILED (5)           backed out ("Please visit again")
--        LINKUP_CONNECTION_ERROR (6) the link broke
--   32 CloseLink          drops the held link
--   33 ColosseumPlayerSpotTriggered / 34 PlayerEnteredTradeSeat
--   FRLG 0x1000+32 EnterColosseumPlayerSpot / 0x1000+33 EnterTradeSeat
--                         the seat: the held session goes on into its battle
--                         or trade, and the player stays in the room for
--                         another (step off the spot and back on).  The room's
--                         door is the cartridge's dynamic warp, which
--                         SetCableClubWarp (special 1) points at the 2F door
--                         the script walked them through; the 2F's own
--                         ON_FRAME (VAR_CABLE_CLUB_STATE) walks them out.  A
--                         friend who has gone: the same way back at once.
--
-- 30 TryRecordMixLinkup stays LINKUP_FAILED: record mixing has no session
-- in the port to run.
--
-- THE WIRELESS ADAPTER (Emerald and FireRed / LeafGreen share these names;
-- FRLG's specials are remapped onto the Emerald indexes at import):
--   415 IsWirelessAdapterConnected  TRUE when this build can go online
--                         (Platform.online(): direct or relay play, and a
--                         link stack): the Union Room and the Direct Corner
--                         open instead of "the adapter isn't connected"
--   416 TryBecomeLinkLeader / 417 TryJoinLinkGroup   the Direct Corner's
--                         group: VAR_0x8004 LINK_GROUP_* -> the link HOST /
--                         JOIN ("connect"), VAR_RESULT LINKUP_SUCCESS;
--                         the script walks the player into the corner's door
--                         and its `waitstate` is where union_room.c's
--                         Task_StartActivity warps (WarpForCableClubActivity:
--                         SetCableClubWarp, VAR_CABLE_CLUB_STATE, the Trade
--                         Center at (5,8) / the Colosseum at (6,8)); the
--                         room's own seat specials run the trade or battle
--                         and ReturnFromLinkRoom brings them out as for the
--                         cable
--   418 RunUnionRoom      the Union Room (after warpspinenter MAP_UNION_ROOM):
--                         LinkRooms.union -- the players of the world you are
--                         in, or a link code -- then back to the 2F door, where
--                         VAR_CABLE_CLUB_STATE = USING_UNION_ROOM walks them
--                         out (CableClub_EventScript_ExitUnionRoom)

local Commands = require("src.script.Commands")
local LinkRooms = require("src.online.LinkRooms")

local M = {}

M.LINKUP_SUCCESS, M.LINKUP_DIFF_SELECTIONS = 1, 3
M.LINKUP_WRONG_NUM_PLAYERS, M.LINKUP_FAILED, M.LINKUP_CONNECTION_ERROR = 4, 5, 6
M.USING_SINGLE_BATTLE, M.USING_DOUBLE_BATTLE, M.USING_MULTI_BATTLE = 1, 2, 5

M.RESULT = {
  linked = M.LINKUP_SUCCESS, mismatch = M.LINKUP_DIFF_SELECTIONS,
  cancelled = M.LINKUP_FAILED, noconnect = M.LINKUP_FAILED,
  failed = M.LINKUP_CONNECTION_ERROR,
}

function M.install(G3)
  local S = G3.SPECIALS
  local setVar, getVar, VAR_RESULT = G3.setVar, G3.getVar, G3.VAR_RESULT

  local function linkup(ctx, room)
    local result = LinkRooms.await(ctx, function(done)
      LinkRooms.open(ctx.game, room, { phase = "connect", arrivalShift = 1 }, done)
    end)
    local code = M.RESULT[result] or M.LINKUP_FAILED
    setVar(ctx.save, VAR_RESULT, code)
    return code
  end

  S[28] = function(ctx)
    local mode = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
    if mode == M.USING_MULTI_BATTLE then
      -- the 4-player multi (src/online/MultiBattle.lua): the counter runs
      -- the whole room (LEADER / JOIN, the code, the teams, the battle);
      -- afterwards the script's "please visit again" closes it
      if LinkRooms.available() and ctx.game and ctx.game.stack then
        local r = require("src.online.MultiBattle").clubEntry(ctx, { title = "MULTI BATTLE" })
        M.lastMulti = r
        setVar(ctx.save, VAR_RESULT, r == "failed" and M.LINKUP_CONNECTION_ERROR or M.LINKUP_FAILED)
        return
      end
      setVar(ctx.save, VAR_RESULT, M.LINKUP_WRONG_NUM_PLAYERS)
      return
    end
    linkup(ctx, mode == M.USING_DOUBLE_BATTLE and "battle2" or "battle")
  end
  S[29] = function(ctx) linkup(ctx, "trade") end

  local function closeLink() LinkRooms.close() end
  S[32] = closeLink

  local function seat(ctx)
    local result = LinkRooms.await(ctx, function(done) LinkRooms.resume(ctx.game, done) end)
    if result == "nosession" then return end
    if LinkRooms.pending() then return end   -- still linked: the room goes on
    -- ReturnFromLinkRoom: back where SetCableClubWarp (special 1) left us
    local back = ctx.save and ctx.save.gen3CableClubReturn
    if back and back.map and back.x and back.y and ctx.runner and ctx.overworld then
      Commands.warp(ctx, back.map, back.x, back.y, "down")
    end
  end
  S[33] = seat
  S[34] = seat
  S[0x1000 + 32] = seat   -- FRLG EnterColosseumPlayerSpot
  S[0x1000 + 33] = seat   -- FRLG EnterTradeSeat
  M.seat = seat

  -- ---- the wireless adapter ------------------------------------------------
  S[415] = function(ctx)
    local yes = M.adapter() and 1 or 0
    setVar(ctx.save, VAR_RESULT, yes)
    return yes
  end

  local function wirelessGroup(ctx, role)
    local group = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
    local spec = M.LINK_GROUPS[group]
    if group == M.LINK_GROUP_MULTI and ctx.game and ctx.game.stack then
      -- the 4-player multi (src/online/MultiBattle.lua): the leader / the
      -- joiners run the whole group here, battle included; LINKUP_FAILED
      -- afterwards takes the script back to its own menu
      local r = require("src.online.MultiBattle").clubEntry(ctx, { role = role, title = "MULTI BATTLE" })
      M.lastMulti = r
      setVar(ctx.save, VAR_RESULT, r == "failed" and M.LINKUP_CONNECTION_ERROR or M.LINKUP_FAILED)
      return
    end
    if not spec then
      -- the record corner, Berry Crush and the minigames: two games' links
      -- only carry trades and battles in this port
      LinkRooms.await(ctx, function(done)
        ctx.game.stack:push(require("src.render.TextBox").new(ctx.game,
          group == M.LINK_GROUP_MULTI and M.TEXT_TWO_ONLY or M.TEXT_NOT_HERE, function() done() end))
      end)
      setVar(ctx.save, VAR_RESULT, M.LINKUP_FAILED)
      return
    end
    local result = LinkRooms.await(ctx, function(done)
      LinkRooms.open(ctx.game, spec.room, { role = role, phase = "connect", arrivalShift = 1 }, done)
    end)
    M.lastWireless = result
    if result == "linked" then
      M.pendingRoom = spec
      M.skipWait = true   -- the `waitstate` right after this special
      setVar(ctx.save, VAR_RESULT, M.LINKUP_SUCCESS)
    elseif result == "failed" then
      setVar(ctx.save, VAR_RESULT, M.LINKUP_CONNECTION_ERROR)
    else
      -- backed out, or the friend gathered for something else: back to the
      -- leader menu, as the cartridge's LINKUP_FAILED
      if result == "mismatch" then LinkRooms.close() end
      setVar(ctx.save, VAR_RESULT, M.LINKUP_FAILED)
    end
  end
  S[416] = function(ctx) return wirelessGroup(ctx, "host") end
  S[417] = function(ctx) return wirelessGroup(ctx, "join") end

  -- the `waitstate` after the corner's door: Task_StartActivity's warp
  local waitState = Commands.g3_wait_state
  Commands.g3_wait_state = function(ctx, ...)
    -- `special 416; waitstate; return`: that one is the special's own wait,
    -- which has already answered.  The script's walk to the corner's door
    -- comes next, and ITS `waitstate` is where the warp happens.
    if M.skipWait then
      M.skipWait = nil
      return
    end
    local spec = M.pendingRoom
    if spec and ctx.runner and ctx.overworld and LinkRooms.pending() then
      M.pendingRoom = nil
      setVar(ctx.save, 0x8004, spec.service)
      setVar(ctx.save, M.cableClubStateVar(), spec.service)
      if S[1] then S[1](ctx) end   -- SetCableClubWarp: the door, for the way back
      local frlg = M.isFRLG()
      Commands.g3_warp(ctx, frlg and spec.frlg[1] or spec.em[1], frlg and spec.frlg[2] or spec.em[2],
                       255, spec.x, spec.y)
      return
    end
    M.pendingRoom = nil
    if waitState then return waitState(ctx, ...) end
  end

  -- ---- the Union Room ----------------------------------------------------
  S[418] = function(ctx)
    M.lastUnion = LinkRooms.await(ctx, function(done) LinkRooms.union(ctx.game, done) end)
    -- leaving the room: ReturnFromLinkRoom, back to the door SetCableClubWarp
    -- kept; the 2F's ON_FRAME (VAR_CABLE_CLUB_STATE = USING_UNION_ROOM) walks
    -- the player out
    local back = ctx.save and ctx.save.gen3CableClubReturn
    if back and back.map and back.x and back.y and ctx.runner and ctx.overworld then
      Commands.warp(ctx, back.map, back.x, back.y, "down")
    end
  end
end

-- SetCableClubWarp (Gen3Commands' special 1 calls this) is the room door's
-- dynamic warp too (the rooms' warps name MAP_G127_N127): walking out of the
-- room ends the link at the 2F door.  The script has walked the player THROUGH
-- the door by now; the way back is the door itself (the cartridge's warp event
-- in front of them).
function M.afterCableClubWarp(ctx)
  local back = ctx.save and ctx.save.gen3CableClubReturn
  if not (back and LinkRooms.pending()) then return end
  local x, y = M.doorNear(ctx, back)
  if x then back.x, back.y = x, y end
  ctx.save.gen3DynamicWarp = { map = back.map, x = back.x, y = back.y, warp = 0xFF }
end

-- the warp cell at most two steps from where the door walk left the player
function M.doorNear(ctx, pos)
  local def = ctx.game and ctx.game.data and ctx.game.data.maps and ctx.game.data.maps[pos.map]
  local best, bx, by = 3, nil, nil
  for _, w in ipairs(def and def.warps or {}) do
    local d = math.abs((w.x or 0) - pos.x) + math.abs((w.y or 0) - pos.y)
    if d < best then best, bx, by = d, w.x, w.y end
  end
  return bx, by
end

-- the Direct Corner's groups (include/constants/union_room.h LINK_GROUP_*)
-- and where union_room.c's Task_StartActivity sends each: the map's
-- group / number in Emerald and in FireRed (data/maps/map_groups.json)
M.LINK_GROUP_MULTI = 2
M.LINK_GROUPS = {
  [0] = { room = "battle", service = M.USING_SINGLE_BATTLE, em = { 25, 24 }, frlg = { 0, 0 }, x = 6, y = 8 },
  [1] = { room = "battle2", service = M.USING_DOUBLE_BATTLE, em = { 25, 24 }, frlg = { 0, 0 }, x = 6, y = 8 },
  [3] = { room = "trade", service = 3, em = { 25, 25 }, frlg = { 0, 1 }, x = 5, y = 8 },
}
M.TEXT_TWO_ONLY = "Only two games can link here."
M.TEXT_NOT_HERE = "Only trades and battles\ncan link here."

function M.isFRLG()
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  local v = okV and GameVersion.get() or nil
  return v == "firered" or v == "leafgreen"
end

-- VAR_CABLE_CLUB_STATE: Emerald 0x4087, FireRed / LeafGreen 0x406F
function M.cableClubStateVar()
  return M.isFRLG() and 0x406F or 0x4087
end

-- the wireless adapter: a build that can go online and a link stack
function M.adapter()
  local okP, Platform = pcall(require, "src.core.Platform")
  local on = false
  if okP and Platform.online then
    local okO, o = pcall(Platform.online)
    on = okO and type(o) == "table" and (o.available or o.relayOnly) and true or false
  end
  return on and LinkRooms.available()
end

return M
