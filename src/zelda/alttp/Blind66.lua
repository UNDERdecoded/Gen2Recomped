-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLIND'S PICTURE 21, THE MAIDEN HE STILL WEARS (round 66). When the maiden
-- is led into the light, Blind_SpawnFromMaiden starts Blind with sprite
-- graphics 21 (aux2 192: the message at 80, the boss poof at 24).
-- Blind_Draw draws pictures >= 15 from kBlindPoof_Dmd (GBA 0x17B1AC, the
-- entry counts 0x17B308): picture 21 is its last group, two 16x16 entries
-- with chars 0x40 / 0x42 on OBJ page 0 (flags 0x0B xor Blind's 1). Those are not Blind's
-- sheet: they are the follower slot. Tagalong_Draw (GBA 0x0811571C) puts
-- every follower's head at char 0x40 (0x081159CE: (flags << 8) | 0x40) and
-- its body at 0x42, with the frame's tiles DMA'd there from the follower
-- sheet (kTagalongDmaAndFlags 0x0817EA0E: dma6 head, dma7 body). The
-- follower is gone when Blind appears, so the slot keeps the maiden's last
-- frame and Blind shows her. The port drew those chars from Blind's sheet
-- (a broken picture).
--
-- Ported: Smiths.drawFollower remembers the last frame it drew per
-- follower (the slot's contents); picture 21's two entries are drawn from
-- follower 6's sheet with that frame's dma6 / dma7, at kBlindPoof_Dmd's
-- offsets with the entries' flags (palette, flips) xor Blind's.
-- No new import data (the poof table, Tagalong_Draw's tables are read by
-- ThievesTown.lua / Smiths.lua already).

local bit = require("bit")
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

local M = {}

M.PICTURE = 21          -- Blind_SpawnFromMaiden's sprite graphics
M.FOLLOWER = 6          -- the blind maiden
M.HEAD, M.BODY = 0x40, 0x42   -- Tagalong_Draw's chars (OBJ page 0)

-- the follower slot's last frame: { dma6, dma7 } per follower (per sprite set)
function M.slot(spr, f)
  return spr and spr.tag66 and spr.tag66[f]
end

-- the entries of picture 21 as draw items { x, y, follower var | nil, char, flags }
function M.items(tb, slot, f)
  local j = M.PICTURE - 15
  local o0, o1 = tb.poofOff[j], tb.poofOff[j + 1]
  if not (o0 and o1) then return nil end
  local out = {}
  for i = o0 + 1, o1 do
    local e = tb.poof[i]
    if e then
      local fl = bxor(e[4], f)
      local var
      if band(fl, 1) == 0 and slot then
        if e[3] == M.HEAD then var = slot[1] elseif e[3] == M.BODY then var = slot[2] end
      end
      out[#out + 1] = { e[1], e[2], var, e[3], fl, e[5] }
    end
  end
  return out
end

-- no ROM reads (ExtractA27's EXTRA list wants an extract)
function M.extract() return { v = 1 } end

-- the frame Tagalong65.draw shows for the trail (direction, walk step)
function M.trailFrame(game, tr)
  local q = tr and tr.t and tr.t[tr.v2]
  if not q then return nil end
  local d = math.floor((q[3] or 2) / 2)
  if d < 0 or d > 3 then d = 1 end
  local walk = tr.v1 ~= tr.v2
  local av = walk and band(rshift(game.frame or 0, 1), 4) or 4
  return d + av
end

function M.install(G)
  local Sm = require("src.zelda.alttp.Smiths")
  -- the slot's contents follow the follower's frame each game frame (the
  -- harness and a skipped draw keep it too)
  local E = require("src.zelda.alttp.Ending27")
  if not E.blind66 then
    E.blind66 = true
    local ff0 = E.followerFrame
    function E.followerFrame(game)
      if (game.progress.follower or 0) == M.FOLLOWER and game.maidenTrail then
        local tb = Sm.tabs and Sm.tabs(game)
        local fr = M.trailFrame(game, game.maidenTrail)
        local d = tb and tb.tagDma
        if fr and d and d[fr * 3 + 1] then game.tag66 = { d[fr * 3 + 1], d[fr * 3 + 2], fr } end
      end
      return ff0(game)
    end
  end
  if not Sm.blind66 then
    Sm.blind66 = true
    local df0 = Sm.drawFollower
    function Sm.drawFollower(spr, tb, f, dir, walk, step, x, y)
      local av = walk and band(step, 4) or 4
      local frame = dir + av
      local d = tb.tagDma
      if spr and d and d[frame * 3 + 1] then
        spr.tag66 = spr.tag66 or {}
        spr.tag66[f] = { d[frame * 3 + 1], d[frame * 3 + 2], frame }
      end
      return df0(spr, tb, f, dir, walk, step, x, y)
    end
  end
  local TT = require("src.zelda.alttp.ThievesTown")
  if TT.blind66 then return end
  TT.blind66 = true
  local dr0 = TT.draw
  function TT.draw(spr, a, x, y, frame, game)
    if a.laser or a.A == 2 or a.A == 1 or (a.gfx or 0) ~= M.PICTURE then return dr0(spr, a, x, y, frame, game) end
    local g = game or a.game
    local tb = spr.data and spr.data.t and spr.data.t.d26 and spr.data.t.d26.thieves
    local slot = M.slot(spr, M.FOLLOWER) or (g and g.tag66)
    if not (tb and slot and Sm.tile16) then return dr0(spr, a, x, y, frame, game) end
    local items = M.items(tb, slot, a.drawFl or 1)
    if not items then return dr0(spr, a, x, y, frame, game) end
    for _, it in ipairs(items) do
      local hf, vf = band(it[5], 0x40) ~= 0, band(it[5], 0x80) ~= 0
      if it[3] then
        Sm.tile16(spr, M.FOLLOWER, it[3], band(rshift(it[5], 1), 7), x + it[1], y + it[2], hf, vf)
      else
        spr:oam(x + it[1], y + it[2], it[4], it[5], it[6])
      end
    end
    if g then g.blind66 = (g.blind66 or 0) + 1 end
    return true
  end
end

return M
