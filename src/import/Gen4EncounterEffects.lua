-- THE BATTLE TRANSITIONS' PICTURES, out of /graphic/field_encounteffect.narc.
--
-- Platinum's into-battle effects (src/overlay005/encounter_effect_core.c) draw
-- the captured field screen through hardware tricks -- windows, H-blank
-- offsets, master brightness -- that need no art, plus a handful of pictures:
-- the Poke Ball OBJs the trainer effects roll in, the Team Galactic logo, the
-- gym leaders' banners and every boss's mugshot, the Elite Four's animated
-- banner and the "VS". This writes those, as palette INDICES plus their
-- palettes, into the cache module `gen4_encounter_effects`.
--
-- WHY INDICES: one picture can be shown under several palettes (the League
-- banner is one cell bank over five palettes), and the effects fade palettes
-- rather than pixels. Each image is assembled through an IDENTITY palette --
-- colour i is (i, 0, 0) -- so the red channel of the result IS the index the
-- hardware would look up, whatever bank the OAM or the tilemap cell chose.
--
-- Stored per image: `w`, `h`, `x`, `y` (the top-left of the cell relative to
-- its OAM origin, or 0,0 for a background), and `idx`, two hex digits a pixel
-- with 00 transparent. Palettes are stored by their NARC name, 256 { r, g, b }.

local Gen4EncounterEffects = {}

Gen4EncounterEffects.PATH = "/graphic/field_encounteffect.narc"

local IDENTITY = {}
for i = 0, 255 do IDENTITY[i + 1] = { i, 0, 0 } end

local function hexOf(image)
  local out = {}
  local rgba = image.rgba
  for p = 0, image.width * image.height - 1 do
    local r, a = rgba:byte(p * 4 + 1), rgba:byte(p * 4 + 4)
    out[p + 1] = ("%02x"):format(a == 0 and 0 or r)
  end
  return table.concat(out)
end

-- The background banners are 256x256 maps of which only a band is drawn; keep
-- the band (rows with any opaque pixel), and say where it was.
local function cropRows(image)
  local w = image.width
  local top, bottom
  for y = 0, image.height - 1 do
    local row = image.rgba:sub(y * w * 4 + 1, (y + 1) * w * 4)
    local any = false
    for x = 0, w - 1 do
      if row:byte(x * 4 + 4) ~= 0 then any = true break end
    end
    if any then
      top = top or y
      bottom = y
    end
  end
  if not top then return image, 0 end
  local h = bottom - top + 1
  return { width = w, height = h,
           rgba = image.rgba:sub(top * w * 4 + 1, (bottom + 1) * w * 4) }, top
end

function Gen4EncounterEffects.extract(rom)
  local Narc = require("src.import.NarcArchive")
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local Archives = require("src.import.Gen4Archives")
  local raw = rom:read(Gen4EncounterEffects.PATH)
  if not raw then return nil, "no " .. Gen4EncounterEffects.PATH end
  local arc = Narc.parse(raw)
  if not arc then return nil, "field_encounteffect.narc did not parse" end
  local names = Archives.names(Gen4EncounterEffects.PATH)
  local byName = {}
  for i, n in ipairs(names) do byName[n] = i - 1 end
  local function member(name)
    local i = byName[name]
    local b = i and arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end

  local out = { images = {}, palettes = {}, anims = {} }

  local function palette(name)
    if out.palettes[name] ~= nil then return out.palettes[name] end
    local p = member(name) and G.palette(member(name))
    out.palettes[name] = p or false
    return p
  end

  -- An OBJ: every cell of its bank, plus its animation's frames.
  local function obj(key, tiles, cell, anim, pal)
    local sheet = member(tiles) and G.tiles(member(tiles))
    local bank = member(cell) and Cells.parse(member(cell), G)
    if not (sheet and bank) then return end
    local list = {}
    for i, c in ipairs(bank.cells) do
      local image = Cells.assemble(c, sheet, IDENTITY, bank, G)
      if image then
        local x, y = Cells.extent(c)
        list[i] = { w = image.width, h = image.height, x = x, y = y, idx = hexOf(image) }
      end
    end
    out.images[key] = list
    if pal then palette(pal) end
    local a = anim and member(anim) and Anim.parse(member(anim), G)
    if a then
      local seqs = {}
      for s, seq in ipairs(a.sequences or {}) do
        local frames = {}
        for f, fr in ipairs(seq.frames or {}) do
          frames[f] = { cell = fr.cell, duration = fr.duration, x = fr.x, y = fr.y }
        end
        seqs[s] = frames
      end
      out.anims[key] = seqs
    end
  end

  -- A background: the tilemap composed, cropped to its drawn band.
  local function bg(key, tiles, map, pal)
    local sheet = member(tiles) and G.tiles(member(tiles))
    local m = member(map) and G.tilemap(member(map))
    if not (sheet and m) then return end
    local image = G.compose(m, sheet, IDENTITY)
    if not image then return end
    local band, top = cropRows(image)
    out.images[key] = { { w = band.width, h = band.height, x = 0, y = top, idx = hexOf(band) } }
    palette(pal)
  end

  obj("trainer_low", ".shared/enc_trainer_low.NCGR", ".shared/enc_trainer_low_cell.NCER",
      ".shared/enc_trainer_low_anim.NANR", ".shared/enc_trainer.NCLR")
  obj("trainer_high", ".shared/enc_trainer_high.NCGR", ".shared/enc_trainer_high_cell.NCER",
      ".shared/enc_trainer_high_anim.NANR", ".shared/enc_trainer.NCLR")
  obj("galactic", ".shared/enc_galactic.NCGR", ".shared/enc_galactic_cell.NCER",
      ".shared/enc_galactic_anim.NANR", ".shared/enc_galactic.NCLR")
  palette(".shared/enc_fade.NCLR")
  obj("vs", ".shared/vs.NCGR", ".shared/vs_cell.NCER", ".shared/vs_anim.NANR", ".shared/vs.NCLR")
  obj("frontier_vs", ".shared/frontier_vs.NCGR", ".shared/frontier_vs_cell.NCER",
      ".shared/frontier_vs_anim.NANR")
  obj("league_banner", ".shared/league_banner.NCGR", ".shared/league_banner_cell.NCER",
      ".shared/league_banner_anim.NANR")
  for _, who in ipairs({ "elite_four_aaron", "elite_four_bertha", "elite_four_flint",
                         "elite_four_lucian", "champion_cynthia" }) do
    palette(who .. "/banner.NCLR")
  end
  for _, who in ipairs({ "leader_roark", "leader_gardenia", "leader_wake", "leader_maylene",
                         "leader_fantina", "leader_candice", "leader_byron", "leader_volkner",
                         "castle_valet", "factory_head", "arcade_star", "hall_matron",
                         "tower_tycoon" }) do
    bg(who .. "/banner", who .. "/banner.NCGR", who .. "/banner.NSCR", who .. "/banner.NCLR")
  end
  for _, who in ipairs({ "leader_roark", "leader_gardenia", "leader_wake", "leader_maylene",
                         "leader_fantina", "leader_candice", "leader_byron", "leader_volkner",
                         "elite_four_aaron", "elite_four_bertha", "elite_four_flint",
                         "elite_four_lucian", "champion_cynthia",
                         "castle_valet", "factory_head", "arcade_star", "hall_matron",
                         "tower_tycoon", "player_male", "player_female" }) do
    obj(who .. "/mugshot", who .. "/mugshot.NCGR", who .. "/mugshot_cell.NCER",
        who .. "/mugshot_anim.NANR", who .. "/mugshot.NCLR")
  end
  for k, v in pairs(out.palettes) do if v == false then out.palettes[k] = nil end end
  return out
end

return Gen4EncounterEffects
