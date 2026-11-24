-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 64: the Thieves' Town grate (the gargoyle's door in the Village of
-- Outcasts) and Overworld_AlterGargoyleEntrance.
--
-- The port never loaded the grate (it is in the area's sprite list but not
-- in any ported sprite set), so the statue's door stayed shut and entrance
-- 52's door could not be reached.
--
-- GBA, read at import from the code below:
--   * the sprite's type: the entry of the sprite routine table (literal
--     0x080C3412) that holds the grate's routine 0x080D2CE8;
--   * its prep 0x080D2C7C: gone if save_ow_event_info[area] (literal
--     0x080D2C82) & `movs #n` 0x080D2C86; else x (+0xEE2 / +0xF02, the SNES 0x0D10 / 0x0D30)
--     - `subs #n` 0x080D2CA4;
--   * its routine 0x080D2CE8 (after PrepOamCoord / ReturnIfInactive /
--     CheckIfLinkIsBusy): touching Link (Sprite_CheckDamageToLink_same_layer
--     0x080C500C) sets link_need_for_pullforrupees_sprite (+0x188F) and the
--     sprite's mark (+0xF62); not touching with the mark: the flag cleared,
--     and when Link pulls (+0x1791 & 1): sound `movs r1, #n` 0x080D2D4A
--     (sprite pan 0x080CF0AC), bl 0x0808F1C4 at 0x080D2D50, the debris
--     (0x080F4CB8), the grate gone;
--   * Overworld_AlterGargoyleEntrance 0x0808F1C4: map16 position (literal
--     0x0808F1C8) <- tile (literal 0x0808F1D6, a map16 number * 4: the
--     draw 0x0808B8B8 indexes the map16 table by it); then from tile
--     (literal 0x0808F1E2) on, each call drawing one and stepping the tile
--     by one map16 and the position by 2 (0x0808B9F8 / 0x0808B948):
--     position (`movs; lsls` 0x0808F1DC) one, (literal 0x0808F1F0) two,
--     (literal 0x0808F204) two; save_ow_event_info[area] (literal
--     0x0808F218) |= `movs #n` 0x0808F21C; sound `movs r0, #n` 0x0808F222.
--     The call sites are checked to be those draws.
--
-- Ported: the grate where the area's list puts it (that list is the port's
-- own import), the contact and the pull, the tiles drawn and kept (drawn
-- again whenever the area loads with the bit set), the sounds.
--
-- OURS: the pull is R held with up / down while touching the grate (the
-- cartridge's pull state is not ported; the port's statues use the same
-- keys), and the door opens at the pull, not the frame Link's pull ends the
-- contact; the debris sprite (0x080F4CB8) is not drawn.

local M = {}

local bit = require("bit")
local band, bor = bit.band, bit.bor

M.GRATE_FN = 0x080D2CE8
M.ALTER_FN = 0x0808F1C4
M.DRAW1, M.DRAW_STEP, M.DRAW_STEP2 = 0x0808B8B8, 0x0808B9F8, 0x0808B948
M.EVENT_BASE = 0x02002280          -- save_ow_event_info (RAM)
M.SITES = {
  routineLit = 0x080C3412, prepEvent = 0x080D2C82, prepMask = 0x080D2C86, prepX = 0x080D2CA4,
  snd = 0x080D2D4A, alterCall = 0x080D2D50,
  pos0 = 0x0808F1C8, tile0 = 0x0808F1D6, pos1 = 0x0808F1DC, tile1 = 0x0808F1E2,
  pos2 = 0x0808F1F0, pos3 = 0x0808F204, event = 0x0808F218, bit = 0x0808F21C, snd2 = 0x0808F222,
}
-- the draws after the first, per position: { position site, calls, the call sites }
M.GROUPS = {
  { "pos1", { 0x0808F1EC } },
  { "pos2", { 0x0808F1F8, 0x0808F200 } },
  { "pos3", { 0x0808F20C, 0x0808F214 } },
}
M.SPRITE_TYPES = 243

-- ------------------------------------------------------------ import
function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function imm(at, want)
    local v, form = RT.codeImm(rom, at)
    if want and form ~= want then return nil end
    return v
  end
  local t = {}
  local rt = imm(S.routineLit, "ldr")
  if rt then
    for i = 0, M.SPRITE_TYPES - 1 do
      if rom:u32(rt - 0x08000000 + i * 4) == M.GRATE_FN + 1 then t.type = i break end
    end
  end
  local ev1, ev2 = imm(S.prepEvent, "ldr"), imm(S.event, "ldr")
  t.area = ev2 and ev2 - M.EVENT_BASE or nil
  t.mask = imm(S.prepMask, "movs")
  t.bit = imm(S.bit, "movs")
  t.xAdj = imm(S.prepX, "subs")
  t.snd = imm(S.snd, "movs")
  t.snd2 = imm(S.snd2, "movs")
  local okCalls = RT.blTarget(rom, S.alterCall) == M.ALTER_FN and RT.blTarget(rom, 0x0808F1D8) == M.DRAW1
  -- the placements: { area-relative map16 byte position, map16 number }
  t.tiles = {}
  local p0, i0 = imm(S.pos0, "ldr"), imm(S.tile0, "ldr")
  local i1 = imm(S.tile1, "ldr")
  if p0 and i0 and i1 then
    t.tiles[1] = { p0, math.floor(i0 / 4) }
    local id = math.floor(i1 / 4)
    for _, g in ipairs(M.GROUPS) do
      local p = imm(S[g[1]])
      for _, site in ipairs(g[2]) do
        local tg = RT.blTarget(rom, site)
        if tg ~= M.DRAW_STEP and tg ~= M.DRAW_STEP2 then okCalls = false end
        if p then t.tiles[#t.tiles + 1] = { p, id } end
        id, p = id + 1, p and p + 2
      end
    end
  end
  t.map16 = {}
  for _, e in ipairs(t.tiles) do t.map16[e[2]] = rom:bytesU16(R.map16 + e[2] * 8, 4) end
  check(t.type and ev1 == ev2 and t.area and t.area >= 0x40 and t.area < 0x80 and t.mask and t.mask == t.bit
        and t.xAdj and t.snd and t.snd2 and okCalls and #t.tiles == 6 and i0 % 4 == 0 and i1 % 4 == 0,
        "the gargoyle grate (type %s, area %s, %d tiles)", tostring(t.type), tostring(t.area), #t.tiles)
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.grate64 end
M.tab = tab

local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end
function M.opened(game, T)
  return band(events(game)[tostring(T.area)] or 0, T.bit) ~= 0
end

-- the persistent map16 (Overworld_DrawMap16_Persist) at an area-relative byte position
local function draw16(game, pos, id)
  local idx = game.data.roomIdx
  if not (idx and idx.map16) then return end
  if not idx.map16[id] then idx.map16[id] = tab(game).map16[id] end
  local a = game.area
  game:owSetMap16(a.x + (pos % 128) / 2 * 16, a.y + math.floor(pos / 128) * 16, id)
end
function M.drawTiles(game, T)
  for _, e in ipairs(T.tiles) do draw16(game, e[1], e[2]) end
end

-- the grate's spot from the area's sprite list (the prep's x adjust)
function M.grateSpot(game, T)
  local npc = game.data.t and game.data.t.npc
  if not (npc and game.area) then return nil end
  local prog = game.storyProgress and game:storyProgress() or 1
  local phase = (prog == 2 and 2) or (prog == 3 and 3) or 1
  local list = npc.ow[phase] and npc.ow[phase][game.area.parent + 1]
  for _, e in ipairs(list or {}) do
    if e[3] == T.type then return game.area.x + e[2] * 16 - T.xAdj, game.area.y + e[1] * 16 end
  end
  return nil
end

local function held(game, k) local i = game.input; return i and i.isDown and i.isDown(k) end

-- Overworld_AlterGargoyleEntrance
function M.open(game, T)
  M.drawTiles(game, T)
  local e = events(game)
  e[tostring(T.area)] = bor(e[tostring(T.area)] or 0, T.bit)
  local Sfx = require("src.zelda.alttp.Sfx")
  pcall(Sfx.start, game, T.snd, "grate")
  pcall(Sfx.start, game, T.snd2, "gargoyle")
  game.gratesOpened64 = (game.gratesOpened64 or 0) + 1
end

-- one overworld frame (before Link's own)
function M.frame(game)
  local T = tab(game)
  if not T or game.state ~= "play" or not game.area or game.link.world ~= "dw" then return end
  local key = game.area.parent
  if game.area.parent ~= T.area then game.grate64 = nil; game.grate64Key = nil return end
  if M.opened(game, T) then
    if game.grate64Key ~= key then game.grate64Key = key; M.drawTiles(game, T) end
    game.grate64 = nil
    return
  end
  game.grate64Key = key
  if game.textBox or game.scroll then return end
  local g = game.grate64
  if not g then
    local x, y = M.grateSpot(game, T)
    if not x then return end
    g = { type = T.type, x = x, y = y, A = 0 }
    game.grate64 = g
  end
  local A = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if not cb then return end
  local hx, hy, hw, hh = A.hitbox(cb, g)
  local lx, ly, lw, lh = A.linkBox(game.link)
  if A.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh) then
    -- link_need_for_pullforrupees_sprite: the action button pulls, no dash
    g.A = 1
    game.pullNeed64 = true
    if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
    if game.link.facing == 0 and held(game, game.actionKey and game:actionKey() or "r") and (held(game, "down") or held(game, "up")) then
      game.pullNeed64 = nil
      game.grate64 = nil
      M.open(game, T)
    end
  elseif g.A == 1 then
    game.pullNeed64 = nil
    g.A = 0
  end
end

-- ------------------------------------------------------------ install
function M.install(G)
  if G.grate64Installed then return end
  G.grate64Installed = true
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    M.frame(self)
    return owFrame(self, inp)
  end
end

return M
