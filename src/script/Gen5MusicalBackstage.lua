-- src/script/Gen5MusicalBackstage.lua -- THE MUSICAL'S BACKSTAGE (zone 78).
--
-- READ (Black's scripts, member 156; the zone's entries in the map_scripts
-- pool): Z078's entries are 1 S0525 (on transition: vars 0x4021..0x4024 =
-- 0x169 0x27 of the four performers -- the four objects' sprites, graphics
-- 163..166), 2 S055B (on load: nothing), 3 S055D (the owner's welcome: the
-- show's type, then "{VAR4} will participate with {VAR3}!" for each of the
-- four, 0x05D 5 / 6; it ends on 0x16B 0x0E 0x0B), 4 S069E ("Let's go up on
-- stage!", 0x16B 0x11), 5 S0707 (the owner's review of each performer by
-- rank, 0x169 0x25 / 0x26 / 0x21, then the fans' flags).
--
-- THE ORDER IS musical_event.c's, READ FROM CODE (Black, overlay 10). 0x167
-- mode 0 / 1 (0x0215D34C) makes the event's work with 0x02155A98 -- the
-- program (0x02157028), the lineup shuffled ten times (+0x44, the player's
-- slot +0x4C = lineup[0]) -- and its state machine 0x02155C0C (state +0xC,
-- 0xD offline, 0xB wireless) then runs, offline:
--   0xD  warp to zone 78 at (8 + 2 * slot, 12) (0x021567D8: 0x0216FEFC is
--        (8.5, 0, 12.5) in tiles, the slot added as slot << 17), facing 0
--   0xE  run zone script 3 (0x02156888 -> 0x02158768: S055D the welcome)
--   0, 1 the field closed (0x02156770), then 3: the Dress Up app
--        (musical_dressup_sys.c, proc 0x02172724), 4 its end -> 0x10
--   0x10 the field back (0x02156710), 0x11 zone script 4 (S069E "Let's go up
--        on stage!"), 0x12 the field closed
--   5, 6 the stage app (musical_stage_sys.c, proc 0x02172748)
--   7, 8 the photo app (overlay 112, proc 0x021F8360; it asks to keep the
--        Musical Photo) -> 0x13
--   0x13 the field back, the fans (0x02156530) and the record (0x02156420)
--   0x14 zone script 5 (S0707, the owner's review)
--   2    the work freed (0x02155F4C), warp to zone 77 (0x02156824): offline
--        (14.5, 12.5) = (14, 12), wireless (10, 12), facing 1
--   9    run script 10444 (0x28CC; wireless 10445 from state 0x1A), the
--        lobby's M0892 S01CF (0x16B 0x15), 0xA the end
-- 0x16B 0x0E / 0x0F / 0x11 (0x0215DC96 / DCC0 / DCE8) do nothing without a
-- wireless partner (work +4): the scripts' own ends move the event on, not
-- those calls. The facing values (0 up, 1 down) are the warp's u16 argument
-- (ov20 0x021854B0), read as the field's direction codes (INFERRED). The
-- player stands in their own lineup slot -- 0x169 0x27 gives that slot's
-- object sprite 0, an empty one, the avatar standing in for it (INFERRED).
--
-- 0x169 0x27 <k> (READ, ov10 0x021569EC -> 0x02157374): 0 for the player,
-- else byte +2 of the show's performer record (the import's `personality`
-- low byte) -- an overworld sprite. 0x05D (READ, ov10 0x0215D884): kind 2
-- the show's name (0x02156914); kind 5 (0x02156A3C) the trainer -- the
-- player's name, else system bank 76 (0x4C) entry = record byte +3
-- (0x02157384); kind 6 (0x02156AD4) the Pokemon -- the player's Pokemon's
-- nickname, else system bank 77 (0x4D, "Peeks", "Mr. Sal" ...) by the same
-- byte.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}

M.ZONE = "Z078"
M.SLOT_X, M.SLOT_Y = { [0] = 8, 10, 12, 14 }, 12

local function Mu() return require("src.script.Gen5Musical") end
local function Game() return package.loaded["src.core.Game"] end
local function work(ctx) return ctx.game and ctx.game.gen5Musical end

local function entries(game)
  local ms = game and game.data and game.data.map_scripts
  local rec = ms and ((ms.maps and ms.maps[M.ZONE]) or ms[M.ZONE])
  return rec and rec.entries
end

function M.available(game)
  local e = entries(game)
  return e and e[3] and e[4] and e[5] and game.data.maps and game.data.maps[M.ZONE] and true or false
end

local function busy(ow)
  return (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
      or (ow.pendingScripts and #ow.pendingScripts > 0)
      or ow.warping or ow.transition
end

-- 0x167 (state 0xD): into the backstage, the welcome (zone script 3) queued
function M.start(ctx, w)
  if os.getenv and os.getenv("BW_MUSICAL_NOBACKSTAGE") then return false end
  local ow = ctx.overworld
  if not (ow and ow.map and ow.player and M.available(ctx.game)) then return false end
  local p = ow.player
  w.backstage = { phase = "welcome", ret = { map = ow.map.id, x = p.cellX, y = p.cellY } }
  Commands.warp(ctx, M.ZONE, M.SLOT_X[w.playerIndex or 0] or 8, M.SLOT_Y, "up")
  ow.gen5QueuedEntry = { entry = 3, from = w.backstage.ret.map }
  Logger.info("bw musical: backstage, slot %d (welcome queued)", w.playerIndex or 0)
  return true
end

-- 0x16B 0x0E <n> / 0x11: wireless sync points, nothing offline (READ)
function M.event(ctx, fn, a)
  local _ = ctx or fn or a
end

local function queue(ow, b, phase, entry)
  b.phase, b.seen = phase, false
  ow.gen5QueuedEntry = { entry = entry, from = M.ZONE, sameMap = true }
end

-- the lobby's script 10444 (state 9): M0892 S01CF, by the shared band
local function lobbyScript(ow, G, id)
  local ms = G.data and G.data.map_scripts
  local best, label
  for name, band in pairs(ms and ms.bands or {}) do
    local first = tonumber(tostring(name):match("^bw_(%d+)$"))
    if first and first <= id and (not best or first > best) and band.entries then
      best, label = first, band.entries[id - first + 1]
    end
  end
  if not label then return end
  local rows = require("src.script.Gen4ScriptVM").compile(G.data, label)
  if not rows then return end
  Logger.info("bw musical: lobby script %d (%s)", id, label)
  ow.runner:run(rows, { mapId = ow.map and ow.map.id })
end

-- every field tick (Gen5PostWarp.update): each state moves on once the zone
-- script before it has run to its end
function M.tick(ow)
  local G = Game()
  local w = G and G.gen5Musical
  local b = w and w.backstage
  if not b or b.phase == "app" or b.phase == "warp" then return end
  -- (the queued entry is taken and started by Gen5PostWarp after this call)
  if ow.gen5QueuedEntry then b.seen = true return end
  if busy(ow) then b.seen = true return end
  -- (a prompt such as the photo's still on top: wait for it)
  if G.stack and G.stack.top and G.stack:top() ~= ow then return end
  if b.phase == "home" then
    w.backstage = nil
    return lobbyScript(ow, G, 10444)
  end
  if b.phase == "photo" then return queue(ow, b, "review", 5) end
  if not b.seen then return end
  local ctx = { game = G, save = G.save, overworld = ow }
  if b.phase == "welcome" then
    -- states 0..4: the Dress Up, then 0x10 / 0x11: zone script 4
    b.phase = "app"
    local pf
    for _, x in ipairs(w.performers or {}) do if x.player then pf = x end end
    local D = require("src.ui.Gen5MusicalDressUp")
    G.stack:push(D.new(G, { mon = pf and pf.mon, show = w.prog and w.prog.show, onDone = function(outfit)
      Mu().dress(w, outfit or {})
      Mu().score(G.data, w.prog, w.performers)
      queue(ow, b, "call", 4)
    end }))
  elseif b.phase == "call" then
    -- states 5..8: the stage, the photo; 0x13 the fans and the record;
    -- 0x14 zone script 5
    b.phase = "app"
    local St = require("src.ui.Gen5MusicalStage")
    G.stack:push(St.new(G, { prog = w.prog, performers = w.performers, onDone = function()
      Mu().finishShow(ctx, w)
      b.phase = "photo"
    end }))
  elseif b.phase == "review" then
    -- state 2: back to the lobby (14, 12) facing down, then state 9
    b.phase = "warp"
    Logger.info("bw musical: back to the lobby")
    ow:startWarpTo("Z077", 14, 12, "down", function() b.phase, b.seen = "home", false end)
  end
end

local function performer(ctx, k)
  local w = work(ctx)
  return w and w.performers and w.performers[(tonumber(k) or 0) + 1]
end

function M.sprite(ctx, k)
  local pf = performer(ctx, k)
  if not pf or pf.player then return 0 end
  return (tonumber(pf.personality) or 0) % 256
end

local function speciesName(data, sp)
  local def = data and data.pokemon and data.pokemon[tonumber(sp) or 0]
  return def and def.name or ""
end

function M.word(ctx, kind, v)
  local data = ctx.game and ctx.game.data
  local w = work(ctx)
  if kind == 2 then
    local index = w and w.prog and w.prog.index or 0
    return data and data.text and data.text[("TEXT_B%04d_%05d"):format(286, 29 + index)] or ""
  end
  local pf = performer(ctx, v)
  if not pf then return "" end
  local n = math.floor((tonumber(pf.personality) or 0) / 256) % 256
  local function sys(bank) return data and data.text and data.text[require("src.import.Gen5Text").label("system", bank, n)] end
  if kind == 6 then
    if pf.player then return (pf.mon and pf.mon.nickname) or speciesName(data, pf.species) end
    return sys(77) or speciesName(data, pf.species)
  elseif kind == 5 then
    if pf.player then return ctx.save and ctx.save.player and ctx.save.player.name or "" end
    return sys(76) or ""
  end
  return ""
end

return M
