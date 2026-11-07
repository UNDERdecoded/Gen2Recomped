-- PLATINUM / HEARTGOLD / SOULSILVER / BLACK / WHITE: THE LINK COUNTERS AND
-- THE GLOBAL TERMINAL (docs/online-design.md 2.7, WS6b), through
-- src/online/LinkRooms.lua (link sessions) and WS7's GtsClient (the GTS).
--
-- The rows below replace the "no Wi-Fi login / no partner" answers.  Each
-- keeps the script's own variable and branches: success takes the script's
-- way in, and "could not connect" lands on the cartridge's own
-- "please visit again".  THE COLOSSEUM IS THE CARTRIDGE'S WALK: the
-- receptionist only links (HOST = become leader / start server, JOIN = join
-- group / client) and answers "gathered"; the script walks the player in
-- and WarpToColosseum takes them to the room; the battle starts when the
-- player steps on a spot (LinkRooms.watchSpots, the C field task's job);
-- the room's exit trigger asks "end communication?" and ScrCmd_204 takes
-- them back to the door, where the floor's frame script walks them out.
--
-- PLATINUM (pokeplatinum res/field/scripts)
--   TryStartGTSApp <conn, dest>       Global Terminal 1F: the GTS; dest 1 when
--                                     it opened, 0 = GlobalTerminal1F_ExitAndEnd
--   GetWiFListValidFriendsCount <d>   B1F Wi-Fi Club: 1 with a link stack, so
--                                     the club opens (0 keeps the no-friends
--                                     / no-login lines)
--   ScrCmd_0A3                        the Wi-Fi Club app: the LINK screen
--   StartBattleServer / Client <mode, ., ., dest>
--                                     2F Colosseum, single and double battles:
--                                     2 once linked (EnterColosseum), _CANCEL
--                                     (1) backs to the leader menu, _ERROR (3)
--   GetCurNetID / WarpToColosseum / FieldCommEnterBattleRoom / 2BB / 204
--                                     the walk in, the spots, the way out
--   OpenBattleRegulationMenu <dest>   3 (no rule set: LinkState's rules
--                                     picker has them)
--   ScrCmd_153                        2F Union Room: LinkRooms.union, then the
--                                     2F's ON_FRAME walks the player back out
-- HEARTGOLD / SOULSILVER (pokeheartgold files/fielddata/script)
--   ScrCmd_166 <dest>                 WFC setup: 0 (nothing to set up)
--   ScrCmd_165 <arg, dest>            Goldenrod Global Terminal: the GTS
--   ScrCmd_226 / ScrCmd_227 <mode, ., ., dest>
--                                     PC 1F Colosseum leader / join: 2 is the
--                                     walk-in, 4 "Please do visit again.",
--                                     1 cancel, 3 error (raw retCodes)
--   ScrCmd_286                        PC 1F Union Room
--   ScrCmd_565 / 564 / 152            PC basement Wi-Fi Club: the friends
--                                     (1), the club = the LINK screen
--   ScrCmd_691 / 663                  the Wi-Fi Plaza: the two-minute wait,
--                                     the lobby (src/online/Plaza.lua)
--   ScrCmd_448 / 451 / 284 / 587 / 449
--                                     the Colosseum walk in, as Platinum's
--                                     WarpToColosseum / GetCurNetID /
--                                     FieldCommEnterBattleRoom / 2BB / 204
-- BLACK / WHITE (ov10 ops, src/import/Gen5ScriptLink.lua)
--   0x13B bwwirelessoff <dest>        1 at a Pokemon Center's link counters
--                                     (the Global Terminal, the Wi-Fi Club);
--                                     the Battle Subway keeps its no-partner
--                                     answer
--   0x13A <var>                       0: no session to drop
--   0x161                             the Wi-Fi Club app: the LINK screen
--   0x162                             the GTS
--   0x103 <var, 4>                    "can't be taken in": 0
--   0x0DB                             the special location (the spot behind
--                                     the desk), where the field comes back
--                                     after 0x161 / 0x162

local Commands = require("src.script.Commands")
local LinkRooms = require("src.online.LinkRooms")
local Strings = require("src.core.Strings")

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end
local function setVar(ctx, var, value)
  local n = tonumber(var)
  if n and ctx.save then G4().setVar(ctx.save, n, value) end
end

Commands.meta = Commands.meta or {}

-- ------------------------------------------------------------ GTS

function Commands.lr_gts(ctx, dest)
  local result = LinkRooms.await(ctx, function(done) LinkRooms.gts(ctx.game, {}, done) end)
  M.lastGts = result
  M.restoreSpot(ctx)
  if dest then setVar(ctx, dest, (result == "done" or result == "closed") and 1 or 0) end
end
Commands.meta.lr_gts = { foreground = true, blocking = true }

function Commands.lr_set(ctx, dest, value)
  setVar(ctx, dest, tonumber(value) or 0)
end

function Commands.lr_wifi_friends(ctx, dest)
  setVar(ctx, dest, LinkRooms.available() and 1 or 0)
end

-- ------------------------------------------------------------ link sessions

function Commands.lr_link_any(ctx)
  M.lastLink = LinkRooms.await(ctx, function(done) LinkRooms.open(ctx.game, "any", {}, done) end)
  if ctx.game and ctx.game.bwLinkSpot then return M.restoreSpot(ctx) end
  M.comeOutAtDoor(ctx)
end

-- HGSS's basement Wi-Fi Club goes in through one door (9,5 / 9,2) and,
-- after RestoreOverworld, comes out of the next (8,2 / 8,5): the field comes
-- back with the player at the door the script animates next.  Read off the
-- script's own rows (the first door load after the app), so a counter whose
-- way out is its way in is left alone.
function M.comeOutAtDoor(ctx)
  local script, pc = ctx.script, ctx.pc
  local ow = ctx.overworld
  local p = ow and ow.player
  if type(script) ~= "table" or not pc or not p then return end
  for i = pc + 1, math.min(#script, pc + 8) do
    local row = script[i]
    if type(row) == "table" and row[1] == "g4_door_anim" and row[2] == "load" then
      local x, y = tonumber(row[5]), tonumber(row[6])
      if x and y and (x ~= p.cellX or y ~= p.cellY) and math.abs(x - p.cellX) <= 1
         and math.abs(y - p.cellY) <= 1 then
        p.cellX, p.cellY = x, y
        p.px, p.py = x * 16, y * 16
      end
      return
    end
  end
end

-- BLACK / WHITE 0x0DB: the player's place (zone, x, y, z, facing) into the
-- game data's special location (handler ov10 0x0215AD7D -> 0x02014184 /
-- 0x0201289C), the place the field comes back to after the counter's app
-- (0x161 the Wi-Fi Club, 0x162 the GTS) -- the spot behind the desk the
-- 2105 walk left the player on, where 2106 walks them out from
function Commands.lr_bw_remember(ctx)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not (ctx.game and ow and ow.map and p) then return end
  ctx.game.bwLinkSpot = { map = ow.map.id, x = p.cellX, y = p.cellY, facing = p.facing }
end

-- the app is over: the field is back at the special location
function M.restoreSpot(ctx)
  local spot = ctx.game and ctx.game.bwLinkSpot
  if not spot then return end
  ctx.game.bwLinkSpot = nil
  local ow = ctx.overworld
  local p = ow and ow.player
  if not (ow and ow.map and p and ow.map.id == spot.map) then return end
  if p.cellX == spot.x and p.cellY == spot.y then return end
  p.cellX, p.cellY = spot.x, spot.y
  p.px, p.py = spot.x * 16, spot.y * 16
  if spot.facing then p.facing = spot.facing end
end
Commands.meta.lr_link_any = { foreground = true, blocking = true }

-- Platinum COMM_CLUB_RET_* / HGSS retCode: 2 = the members are gathered
-- (the script walks the player into the Colosseum), 1 cancel (back to the
-- leader menu), 3 error ("repeat the process from the beginning"), 4 "Please
-- visit again."
M.CLUB = { enter = 2, done = 4, cancel = 1, error = 3 }

-- room: "battle" (single), "battle2" (double), nil (a mix / multi battle:
-- two games only).  THE CARTRIDGE'S WALK IN: the receptionist only links
-- ("connect"); on 2 the script's own EnterColosseum walks the player
-- through the gate and the door and WarpToColosseum takes them to the
-- room, where the battle starts from the spots (lr_battle_room)
local function club(ctx, room, dest, server)
  local game = ctx.game
  if not room then
    LinkRooms.await(ctx, function(done)
      game.stack:push(require("src.render.TextBox").new(game,
        Strings("Only SINGLE and DOUBLE\nBATTLES link here."), function() done() end))
    end)
    setVar(ctx, dest, M.CLUB.cancel)
    return
  end
  local result = LinkRooms.await(ctx, function(done)
    LinkRooms.open(game, room, { role = server and "host" or "join", phase = "connect" }, done)
  end)
  M.lastClub = result
  local code
  if result == "linked" then code = M.CLUB.enter
  elseif result == "cancelled" then code = M.CLUB.cancel
  else
    -- "mismatch": the friend gathered for the other battle -- the cartridge's
    -- groups are per battle type, so this is the "from the beginning" line
    LinkRooms.close()
    code = M.CLUB.error
  end
  setVar(ctx, dest, code)
end

-- GetCurNetID (Platinum) / ScrCmd_451 (HGSS): 0 the leader, 1 the member --
-- the script adds 7 for the room's arrival column
function Commands.lr_net_id(ctx, var)
  local last = LinkRooms.last
  local guest = LinkRooms.pending() ~= nil and last and last.isHost == false
  setVar(ctx, var, guest and 1 or 0)
end

-- WarpToColosseum (Platinum) / ScrCmd_448 (HGSS) <header, warp, x, z, dir>:
-- FieldTask_StartChangeMapColosseum keeps where the player stands (the
-- door) as the special location that ScrCmd_204 / 449 go back to
function Commands.lr_colosseum_warp(ctx, header, x, z, dir)
  local ow = ctx.overworld
  local p = ow and ow.player
  if ctx.game and ow and ow.map and p then
    ctx.game.g4LinkReturn = { map = ow.map.id, x = p.cellX, y = p.cellY }
  end
  return Commands.g4_warp(ctx, header, x, z, dir)
end

-- FieldCommEnterBattleRoom (Platinum) / ScrCmd_284 (HGSS), the room's
-- ON_TRANSITION: the held link goes on once the player stands on a spot
-- (the two-player rooms are the same layout in both games: the arrival
-- row y=11 with its exit trigger, the waitress at (12,4); HGSS's spot grid is
-- not decompiled and is taken to be Platinum's).  The link stays up after a
-- battle, so stepping off a spot and back on starts the next.
function Commands.lr_battle_room(ctx)
  local ow = ctx.overworld
  if not (ctx.game and ow and ow.map) or not LinkRooms.pending() then return end
  local game, map = ctx.game, ow.map.id
  local function watch(again)
    LinkRooms.watchSpots(game, { map = map, spots = LinkRooms.SPOTS_2P, stepOff = again,
      onSeat = function(result)
        M.lastRoom = result
        if LinkRooms.pending() then watch(true) end
      end })
  end
  watch(false)
end

-- ScrCmd_2BB (Platinum) / ScrCmd_587 (HGSS): the end of the link, and
-- EndCommunication on the receptionist's cancel / error arms
function Commands.lr_end_link(ctx)
  if LinkRooms.pending() then LinkRooms.close() end
  LinkRooms.watch = nil
end
function Commands.lr_end_communication(ctx)
  Commands.lr_end_link(ctx)
  if Commands.g4_end_communication then return Commands.g4_end_communication(ctx) end
end

-- ScrCmd_204 (Platinum) / ScrCmd_449 (HGSS): back to the special location
-- (the 2F / 1F door), where the floor's ON_FRAME walks the player out on
-- VAR_COMMUNICATION_LOAD_ACTION (Platinum 0x40D5) / VAR_UNK_4133 (HGSS)
function Commands.lr_return_room(ctx)
  local back = ctx.game and ctx.game.g4LinkReturn
  if not (back and back.map and ctx.runner) then return end
  ctx.game.g4LinkReturn = nil
  return Commands.warp(ctx, back.map, back.x, back.y, "down")
end

-- THE 4-PLAYER MULTI (Platinum and HGSS mode 4): the leader / joiner
-- runs the room through src/online/MultiBattle.lua; the script goes on from
-- the same answers as a single or double
function M.multiClub(ctx, dest, server)
  local r = require("src.online.MultiBattle").clubEntry(ctx, { role = server and "host" or "join" })
  M.lastClub = r
  local code = (r == "win" or r == "lose" or r == "draw") and M.CLUB.done
    or (r == "cancelled" and M.CLUB.cancel) or M.CLUB.error
  setVar(ctx, dest, code)
end

-- Platinum: 1 single, 2 double, 3 mix, 4 multi; 6 (Poffin cooking) keeps
-- Gen4Commands' own local cooks
-- (the PC 2F's VAR_0x8004); the Frontier, contest and Poffin modes (6 and
-- up) keep Gen4Commands' answers
function Commands.lr_pt_club(ctx, mode, dest, server)
  local m = valueOf(ctx, mode)
  if m < 1 or m > 4 or not (ctx.game and ctx.game.stack) then
    return Commands.g4_link_club(ctx, mode, dest, server)
  end
  if m == 4 and LinkRooms.available() then return M.multiClub(ctx, dest, tonumber(server) == 1) end
  return club(ctx, (m == 1 and "battle") or (m == 2 and "battle2") or nil, dest, tonumber(server) == 1)
end
Commands.meta.lr_pt_club = { foreground = true, blocking = true }

-- HGSS: 1 single, 2 double, 3 mix, 4 multi (the four-player menu's row), 37 the
-- other (the PC 1F colosseum's VAR_0x8004); the Frontier's modes keep the old
-- "cancelled" answer
M.HGSS_CLUB_MODES = { [1] = true, [2] = true, [3] = true, [4] = true, [37] = true }
function Commands.lr_hgss_club(ctx, mode, dest, server)
  local m = valueOf(ctx, mode)
  if not M.HGSS_CLUB_MODES[m] or not (ctx.game and ctx.game.stack) then
    return setVar(ctx, dest, M.CLUB.cancel)
  end
  if m == 4 and LinkRooms.available() then return M.multiClub(ctx, dest, tonumber(server) == 1) end
  return club(ctx, (m == 1 and "battle") or (m == 2 and "battle2") or nil, dest, tonumber(server) == 1)
end
Commands.meta.lr_hgss_club = { foreground = true, blocking = true }

-- ------------------------------------------------------------ HGSS Wi-Fi Plaza

-- ScrCmd_691 <dest>: two minutes since the last Plaza visit (the cartridge's
-- RTC seconds against fieldSystem->unkB4)
function Commands.lr_plaza_ready(ctx, dest)
  setVar(ctx, dest, require("src.online.Plaza").ready() and 1 or 0)
end

-- ScrCmd_663 <var>: the Plaza (src/online/Plaza.lua: a world lobby)
function Commands.lr_plaza(ctx)
  M.lastPlaza = LinkRooms.await(ctx, function(done) require("src.online.Plaza").open(ctx.game, done) end)
end
Commands.meta.lr_plaza = { foreground = true, blocking = true }

-- ------------------------------------------------------------ Union Room

-- below = how many cells south of the door the player comes back out:
-- Platinum's 2F walks them out itself (ON_FRAME on
-- VAR_COMMUNICATION_LOAD_ACTION), so 0; HGSS has no such frame script after
-- a same-map return, so the player is set back on the counter's near side
-- (4 below the door: door, gate, counter, the tile they talked from)
function Commands.lr_union(ctx, below)
  M.lastUnion = LinkRooms.await(ctx, function(done) LinkRooms.union(ctx.game, done) end)
  local ow = ctx.overworld
  local p = ow and ow.player
  if ow and ow.map and p and p.cellX and ctx.runner then
    local dy = tonumber(below) or 0
    Commands.warp(ctx, ow.map.id, p.cellX, p.cellY + dy, "down")
  end
end
Commands.meta.lr_union = { foreground = true, blocking = true }

-- ------------------------------------------------------------ Black / White

-- the Pokemon Centers (every one has the Global Terminal and Wi-Fi Club
-- counters at the same cells)
M.BW_CENTERS = {
  Z001 = true, Z008 = true, Z020 = true, Z041 = true, Z065 = true, Z099 = true,
  Z109 = true, Z115 = true, Z122 = true, Z398 = true, Z407 = true, Z413 = true,
  Z425 = true,
}

function Commands.lr_bw_wireless(ctx, dest)
  local here = ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
  if here and M.BW_CENTERS[here] and LinkRooms.available() then
    return setVar(ctx, dest, 1)
  end
  -- the Battle Subway and the rest: as before (Gen5BattleSubway)
  if Commands.g5_subway_wireless then return Commands.g5_subway_wireless(ctx, dest) end
  setVar(ctx, dest, 0)
end

-- BLACK / WHITE 0x103 <var, mode> (gen5-script-link-v23 keeps the mode):
-- mode 4 is the link counters' first question, "how many can't be taken in"
-- (`0x103 v, 4; compare v, 0; if == goto <go on>` at the Global Terminal and
-- the Wi-Fi Club, "You have at least one Pokemon that can't be taken in."),
-- answered 0: nothing the port can't carry.  The other modes are the
-- party's non-egg count, as before.
M.BW_CANT_TAKE_IN = 4

-- ------------------------------------------------------------ lowering

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  local function arg(ins, i) return ins.args and ins.args[i] end
  -- Platinum
  L.trystartgtsapp = function(ins, s) emit(s, { "lr_gts", arg(ins, 2) }) end
  L.getwiflistvalidfriendscount = function(ins, s) emit(s, { "lr_wifi_friends", arg(ins, 1) }) end
  L["0a3"] = function(_, s) emit(s, { "lr_link_any" }) end
  L["153"] = function(_, s) emit(s, { "lr_union" }) end
  -- the Colosseum's rule-set list (battle_regulation_menu.c): 3 is "no
  -- rule set"; the link's own rules picker (WS5) is where the host sets
  -- format, level and clauses
  L.openbattleregulationmenu = function(ins, s) emit(s, { "lr_set", arg(ins, 1), 3 }) end
  L.startbattleserver = function(ins, s) emit(s, { "lr_pt_club", arg(ins, 1), arg(ins, 4), 1 }) end
  L.startbattleclient = function(ins, s) emit(s, { "lr_pt_club", arg(ins, 1), arg(ins, 4), 0 }) end
  -- the walk in and out of the Colosseum (both games)
  local function room(row)
    return function(ins, s)
      local out = { row[1] }
      for i = 2, #row do out[i] = arg(ins, row[i]) end
      emit(s, out)
    end
  end
  L.getcurnetid = room({ "lr_net_id", 1 })
  L.scrcmd_451 = room({ "lr_net_id", 1 })
  L.warptocolosseum = room({ "lr_colosseum_warp", 1, 3, 4, 5 })
  L.scrcmd_448 = room({ "lr_colosseum_warp", 1, 3, 4, 5 })
  L.fieldcommenterbattleroom = room({ "lr_battle_room" })
  L.scrcmd_284 = room({ "lr_battle_room" })
  L["2bb"] = room({ "lr_end_link" })
  L.scrcmd_587 = room({ "lr_end_link" })
  L["204"] = room({ "lr_return_room" })
  L.scrcmd_449 = room({ "lr_return_room" })
  L.endcommunication = room({ "lr_end_communication" })
  L.scrcmd_283 = room({ "lr_end_link" })
  -- HeartGold / SoulSilver
  L.scrcmd_166 = function(ins, s) emit(s, { "lr_set", arg(ins, 1), 0 }) end
  L.scrcmd_165 = function(ins, s) emit(s, { "lr_gts", arg(ins, 2) }) end
  L.scrcmd_226 = function(ins, s) emit(s, { "lr_hgss_club", arg(ins, 1), arg(ins, 4), 1 }) end
  L.scrcmd_227 = function(ins, s) emit(s, { "lr_hgss_club", arg(ins, 1), arg(ins, 4), 0 }) end
  L.scrcmd_286 = function(_, s) emit(s, { "lr_union", 4 }) end
  -- the PC basement's Wi-Fi Club (scr_seq_0164_002): 565 the registered
  -- friends (1 with a link stack: the club opens), 564 "a Wi-Fi connection
  -- is set up", 152 the club itself = the LINK screen (a code is the friend
  -- list; the host picks TRADE or BATTLE)
  L.scrcmd_565 = function(ins, s) emit(s, { "lr_wifi_friends", arg(ins, 1) }) end
  L.scrcmd_564 = function(ins, s) emit(s, { "lr_wifi_friends", arg(ins, 1) }) end
  L.scrcmd_152 = function(_, s) emit(s, { "lr_link_any" }) end
  -- the Wi-Fi Plaza (scr_seq_0164_003, scr_seq_HIROBA): 691 the two-minute
  -- wait, 663 the Plaza
  L.scrcmd_691 = function(ins, s) emit(s, { "lr_plaza_ready", arg(ins, 1) }) end
  L.scrcmd_663 = function(_, s) emit(s, { "lr_plaza" }) end
  -- Black / White
  L.bwwirelessoff = function(ins, s) emit(s, { "lr_bw_wireless", arg(ins, 1) }) end
  L.bw_13A = function(ins, s) emit(s, { "lr_set", arg(ins, 1) or 0x8010, 0 }) end
  L.bw_161 = function(_, s) emit(s, { "lr_link_any" }) end
  L.bw_0DB = function(_, s) emit(s, { "lr_bw_remember" }) end
  L.bw_162 = function(_, s) emit(s, { "lr_gts" }) end
  local nonEggs = L.partycountnotegg
  L.partycountnotegg = function(ins, s)
    if tonumber(arg(ins, 2)) == M.BW_CANT_TAKE_IN then
      return emit(s, { "lr_set", arg(ins, 1), 0 })
    end
    return nonEggs(ins, s)
  end
end

return M
