-- PLATINUM'S HALL OF FAME AND END CREDITS ART, composed from the cartridge.
--
--   /graphic/dendou_demo.narc   the Hall of Fame (src/cutscenes/hall_of_fame.c
--                               lines 690-695), five prebuilt members: 3 the
--                               tiles, 4 the palette (three BG palettes), and
--                               three tilemaps --
--                                 hof_stage    0, BG3, the stage
--                                 hof_overlay  2, BG2, what covers everything
--                                              outside the moving window
--                                 hof_party    1, BG3 for the final group shot
--   /graphic/ending.narc        the credits (src/cutscenes/end_credits), with
--                               its member names (ending.order):
--                                 credits_<time>_bottom / _top   the bike-ride
--                                              backgrounds, morning / day / night
--                                 credits_memory_<who>_<n>       the ten
--                                              memories per player, 256-colour
--                                              over memory_shared.NSCR
--                                 credits_twinleaf_<who>_<n>     the four
--                                              closing Twinleaf pictures
--                                 credits_bike_<who>, _scarf      the player
--                                 credits_object_<n>             Drifloon,
--                                              Wingull, Magnezone...
--
-- Written to assets/generated/gen4/ending/<key>.png, indexed in
-- `gen4_ending_art`.

local Gen4EndingArt = {}

Gen4EndingArt.HOF = "/graphic/dendou_demo.narc"
Gen4EndingArt.CREDITS = "/graphic/ending.narc"
Gen4EndingArt.MEMORIES = {
  lucas = { "route_201_starter", "rowans_lab", "pokemon_center", "valley_windworks", "route_210_psyduck",
            "eterna_forest", "pastoria_great_marsh", "canalave_barry", "lake_acuity", "spear_pillar" },
  dawn = { "route_201_starter", "jubilife_looker", "pokemon_mart", "eterna_cyrus", "hearthome_contest_hall",
           "solaceon_town", "route_216", "lake_valor", "galactic_hq", "spear_pillar" },
}

local function backdrop(pic, colour)
  if not (pic and colour) then return pic end
  local fill = string.char(colour[1], colour[2], colour[3], 255)
  local out = {}
  for p = 0, pic.width * pic.height - 1 do
    local at = p * 4
    if pic.rgba:byte(at + 4) == 0 then out[p + 1] = fill else out[p + 1] = pic.rgba:sub(at + 1, at + 4) end
  end
  return { width = pic.width, height = pic.height, rgba = table.concat(out) }
end

function Gen4EndingArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local A = require("src.import.Gen4Archives")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local out = {}

  local function open(path)
    local bytes = rom:read(path)
    if not bytes then return nil end
    local narc = N.parse(bytes)
    local h, cache = {}, {}
    function h.raw(i)
      local b = narc:get(i)
      if b and G.isCompressed(b) then b = G.decompress(b) end
      return b
    end
    function h.get(name, fn)
      local i = type(name) == "number" and name or A.find(path, name)
      if not i then return nil end
      local key = i .. ":" .. tostring(fn)
      if cache[key] == nil then cache[key] = fn(h.raw(i)) or false end
      return cache[key] or nil
    end
    return h
  end

  -- THE HALL OF FAME
  local hof = open(Gen4EndingArt.HOF)
  if hof then
    local tiles, pal = hof.get(3, G.tiles), hof.get(4, G.palette)
    local stage = G.compose(hof.get(0, G.tilemap), tiles, pal)
    out.hof_stage = backdrop(stage, pal and pal[1])
    out.hof_overlay = G.compose(hof.get(2, G.tilemap), tiles, pal)
    out.hof_party = backdrop(G.compose(hof.get(1, G.tilemap), tiles, pal), pal and pal[1])
  end

  -- THE CREDITS
  local cr = open(Gen4EndingArt.CREDITS)
  if cr then
    local function screen(key, map, tiles, pal, base)
      local p = cr.get(pal, G.palette)
      local pic = G.compose(cr.get(map, G.tilemap), cr.get(tiles, G.tiles), p)
      out[key] = base and backdrop(pic, p and p[1]) or pic
    end
    for _, t in ipairs({ "morning", "day", "night" }) do
      screen("credits_" .. t .. "_bottom", ("background_%s_bottom.NSCR"):format(t),
             ("background_%s_bottom_tiles.NCGR"):format(t), ("background_%s_bottom.NCLR"):format(t), true)
      screen("credits_" .. t .. "_top", ("background_%s_top.NSCR"):format(t),
             ("background_%s_top_tiles.NCGR"):format(t), ("background_%s_top.NCLR"):format(t), true)
    end
    for who, names in pairs(Gen4EndingArt.MEMORIES) do
      for n, name in ipairs(names) do
        screen(("credits_memory_%s_%d"):format(who, n - 1), "memory_shared.NSCR",
               ("memory_%s_%s.NCGR"):format(who, name), ("memory_%s_%s.NCLR"):format(who, name), true)
      end
      for n = 1, 4 do
        screen(("credits_twinleaf_%s_%d"):format(who, n), "twinleaf_shared.NSCR",
               ("twinleaf_%s_%d.NCGR"):format(who, n), ("twinleaf_%s_%d.NCLR"):format(who, n), true)
      end
    end
    -- sprites: the first frame of each sequence, in the cell's own palette
    local function sprite(key, tiles, cells, anim, pal, sequence)
      local sheet, bank, an, colours = cr.get(tiles, G.tiles), cr.get(cells, function(b) return Cells.parse(b, G) end),
        cr.get(anim, function(b) return Anim.parse(b, G) end), cr.get(pal, G.palette)
      if not (sheet and bank and an and colours) then return end
      local frames = Anim.frames(an, sequence or 0)
      local cell = frames and frames[1] and bank.cells[frames[1].cell + 1]
      local pic = cell and Cells.assemble(cell, sheet, colours, bank, G)
      if pic then pic.originX, pic.originY = Cells.extent(cell); out[key] = pic end
      return an
    end
    sprite("credits_bike_lucas", "lucas_bike.NCGR", "lucas_bike_cell.NCER", "lucas_bike_anim.NANR", "lucas_bike.NCLR", 0)
    sprite("credits_scarf_lucas", "lucas_bike.NCGR", "lucas_bike_cell.NCER", "lucas_bike_anim.NANR", "lucas_bike.NCLR", 2)
    sprite("credits_bike_dawn", "dawn_bike_tiles.NCGR", "dawn_bike_cell.NCER", "dawn_bike_anim.NANR", "dawn_bike_tiles.NCLR", 0)
    sprite("credits_scarf_dawn", "dawn_bike_tiles.NCGR", "dawn_bike_cell.NCER", "dawn_bike_anim.NANR", "dawn_bike_tiles.NCLR", 2)
    local an = cr.get("bike_bg_objects_anim.NANR", function(b) return Anim.parse(b, G) end)
    for s = 0, (an and #an.sequences or 0) - 1 do
      sprite("credits_object_" .. s, "bike_bg_objects.NCGR", "bike_bg_objects_cell.NCER", "bike_bg_objects_anim.NANR",
             "bike_bg_objects.NCLR", s)
    end
  end
  -- the 3D props' textures (Gen4EndingArt.models)
  for key, pic in pairs(Gen4EndingArt.modelPictures(rom)) do out[key] = pic end
  return out
end


-- THE STAFF ROLL (src/cutscenes/end_credits/strings.c sEndCreditStringProps):
-- 237 { u16 message (bank 548), u16 y, u16 centred } in overlay 99, found by
-- its first three rows. Each line is printed when the scroll's bottom edge
-- reaches its y and erased sixteen pixels after the top passes it. Also the
-- credits' text palette (ending.narc text.NCLR, member 85) for {COLOR n}.
Gen4EndingArt.ROLL_OVERLAY = 99
Gen4EndingArt.ROLL_SIGNATURE = string.char(0,0, 0,0, 1,0, 1,0, 16,0, 1,0, 2,0, 146,0, 0,0)
Gen4EndingArt.ROLL_COUNT = 237

function Gen4EndingArt.data(rom)
  local out = {}
  local ok, ov = pcall(rom.overlay, rom, Gen4EndingArt.ROLL_OVERLAY)
  local at = ok and ov and ov:find(Gen4EndingArt.ROLL_SIGNATURE, 1, true)
  if at then
    local roll = {}
    for i = 0, Gen4EndingArt.ROLL_COUNT - 1 do
      local o = at + i * 6
      roll[i + 1] = { message = ov:byte(o) + ov:byte(o + 1) * 256, y = ov:byte(o + 2) + ov:byte(o + 3) * 256,
                      centred = (ov:byte(o + 4) + ov:byte(o + 5) * 256) ~= 0 }
    end
    out.roll = roll
  end
  local G = require("src.import.Gen4Graphics")
  local bytes = rom:read(Gen4EndingArt.CREDITS)
  if bytes then
    local narc = require("src.import.NarcArchive").parse(bytes)
    local A = require("src.import.Gen4Archives")
    local i = A.find(Gen4EndingArt.CREDITS, "text.NCLR")
    local b = i and narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    local pal = b and G.palette(b)
    if pal then
      out.textColours = {}
      for k = 1, math.min(16, #pal) do out.textColours[k - 1] = pal[k] end
    end
  end
  -- the Hall of Fame's text, BG1 palette 1, colours (1, 2, 0)
  local hofBytes = rom:read(Gen4EndingArt.HOF)
  if hofBytes then
    local narc = require("src.import.NarcArchive").parse(hofBytes)
    local b = narc:get(4)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    local pal = b and G.palette(b)
    if pal and pal[18] then out.hofText = { ink = pal[18], shadow = pal[19] } end
  end
  out.models = Gen4EndingArt.models(rom)
  return out
end

-- THE CREDITS' 3D (scenes.c Load3DModels*): the morning's two tree rows, the
-- day's lampposts, the night's trees, snowy trees and lampposts -- each BMD0
-- packed as the other model screens' are (Gen4ModelPack, drawn by
-- src/render/Gen4Model.lua), its textures decoded from its own TEX0 and
-- saved beside the credits' pictures as `model_<name>_<texture>`.
Gen4EndingArt.MODELS = { "background_morning_tree_1", "background_morning_tree_2", "background_day_lamppost",
  "background_night_tree_1_normal", "background_night_tree_1_snowy", "background_night_tree_2",
  "background_night_lamppost" }

local function packModels(rom)
  local G = require("src.import.Gen4Graphics")
  local A = require("src.import.Gen4Archives")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local Models = require("src.import.Gen4Models")
  local Pack = require("src.import.Gen4ModelPack")
  local bytes = rom:read(Gen4EndingArt.CREDITS)
  if not bytes then return nil, nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  local records, pictures = {}, {}
  for _, name in ipairs(Gen4EndingArt.MODELS) do
    local i = A.find(Gen4EndingArt.CREDITS, name .. ".BMD0")
    local b = i and narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    local parsed = b and Nsbmd.parse(b)
    local model = parsed and parsed.models and parsed.models[1]
    if model then
      local sections = Nsbmd.sections(b)
      local textures = sections and sections.TEX0 and Models.parse(b, sections.TEX0) or nil
      local packed = Pack.pack(model)
      packed.animations = {}
      for _, shape in ipairs(packed.shapes) do
        if shape.texture and textures then
          local key = ("model_%s_%s"):format(name, shape.texture):gsub("[^%w_]", "_")
          if pictures[key] == nil then
            local index, palette
            for k, t in ipairs(textures.textures) do if t.name == shape.texture then index = k end end
            for k, p in ipairs(textures.palettes) do if p.name == shape.palette then palette = k end end
            pictures[key] = index and Models.decode(textures, b, index, palette or 1) or false
          end
          if pictures[key] then shape.image = "assets/generated/gen4/ending/" .. key .. ".png" end
        end
      end
      packed.name = name
      records[name] = packed
    end
  end
  return records, pictures
end

function Gen4EndingArt.models(rom)
  local records = packModels(rom)
  return records
end

function Gen4EndingArt.modelPictures(rom)
  local _, pictures = packModels(rom)
  local out = {}
  for k, v in pairs(pictures or {}) do if v then out[k] = v end end
  return out
end

return Gen4EndingArt
