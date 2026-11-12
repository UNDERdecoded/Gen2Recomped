-- Round 5 importer pieces for screen effects (runs in the import worker:
-- no love.graphics here).
--
-- BG tile animations (src/backgroundAnimations.c): gUnk_080B755C[area] is a
-- u16 list of animation indices ($FFFF ends), gUnk_080B7278[index] a list of
-- BgAnimationFrame {gfx*, u32 timer}; a NULL gfx ends it (loop back `timer`).
-- Each BgAnimationGfx {u16 vramOffset, u8 size, u8 flags, u32 gfxOffset}
-- is LoadBgAnimationGfx: flags bit 4 (BG_ANIM_PALETTE) = LoadPalettes(src,
-- vramOffset >> 5, size) -- `size` palettes of 16 colours into bank
-- vramOffset / 32 -- otherwise MemCopy of size * 32 bytes of characters to
-- VRAM + vramOffset; bit 7 (BG_ANIM_MULTIPLE) = another entry follows.
--
-- Output: bganim.bin (the bytes) and manifest.bgAnims[area] = list of
-- animations, each a list of frames {timer, patches = {{vram, at, len}},
-- palettes = {{bank, at, count}}}.
local bit = require("bit")
local band = bit.band
local Layout = require("src.zelda.tmc.Layout")

local M = {}

function M.bgAnims(rom, store, manifest)
  local parts, at, out = {}, 0, {}
  for area = 0, 0x8F do
    local lp = rom:ptr(Layout.gUnk_080B755C + 4 * area)
    if lp then
      local list = {}
      for i = 0, 7 do
        local idx = rom:u16(lp + 2 * i)
        if idx == 0xFFFF then break end
        local fp = rom:ptr(Layout.gUnk_080B7278 + 4 * idx)
        if not fp then break end
        local frames = {}
        for k = 0, 31 do
          local q = fp + 8 * k
          local gp = rom:u32(q)
          local timer = rom:u32(q + 4)
          if gp == 0 then frames.loop = band(timer, 0xFF) break end
          local g = rom:ptr(q)
          if not g then break end
          local patches, palettes = {}, {}
          for n = 0, 7 do
            local e = g + 8 * n
            local vram, size, fl = rom:u16(e), rom:u8(e + 2), rom:u8(e + 3)
            local src = Layout.gGlobalGfxAndPalettes + rom:u32(e + 4)
            if size > 0 then
              local bytes = rom:str(src, size * 32)
              if band(fl, 0x10) ~= 0 then
                palettes[#palettes + 1] = { math.floor(vram / 32), at, size }
                patches.palette = true
              else
                patches[#patches + 1] = { vram, at, #bytes }
              end
              parts[#parts + 1] = bytes
              at = at + #bytes
            end
            if band(fl, 0x80) == 0 then break end
          end
          frames[#frames + 1] = { timer = math.max(1, band(timer, 0xFF)), patches = patches, palettes = palettes }
        end
        list[#list + 1] = frames
      end
      if #list > 0 then out[area] = list end
    end
  end
  assert(store:write("bganim.bin", table.concat(parts)))
  manifest.bgAnims = out
end

function M.extract(rom, store, manifest)
  M.bgAnims(rom, store, manifest)
end

return M
