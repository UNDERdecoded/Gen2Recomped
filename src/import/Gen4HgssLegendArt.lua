-- HEARTGOLD / SOULSILVER'S LEGENDARY CUTSCENE ART: /a/1/7/4 (demo/legend.narc).
--
-- The Kimono Girls' dance that calls Ho-Oh to the Bell Tower (HeartGold) and
-- Lugia to the Whirl Islands (SoulSilver) draws its own 3D objects over the
-- field, all out of this archive (pokeheartgold src/field/
-- legend_cutscene_camera.c names every member):
--
--   18 clear bell rising   19 BCA  20 BTP  21 BTA, then idle 22 BCA 23 BTP 24 BTA
--   25 clear bell shimmer  26 BCA  27 BTA
--   32 corner bell         33 BTA
--   28 Lugia eye glimmer   29 BMA  30 BTP  31 BCA
--   34 bird's ring         35 BCA  36 BMA  37 BTP
--   38 SoulSilver waves    39 BCA  40 BTA
--   41..46 / 47..52 HeartGold's falling leaves, BG2 / BG3 tilemaps over the
--   field, on character data 53 and palette 54
--
-- Each model is packed the way the BW title's are (Gen4ModelPack + its own
-- textures), joint animations as packed tracks, texture and material
-- animations as the records Gen4TexAnim evaluates.

local A = { PATH = "/a/1/7/4" }

A.PARTS = {
  bellRise    = { model = 18, anims = { 19, 20, 21 } },
  bellIdle    = { model = 18, anims = { 22, 23, 24 } },
  bellShimmer = { model = 25, anims = { 26, 27 } },
  cornerBell  = { model = 32, anims = { 33 } },
  eyeGlimmer  = { model = 28, anims = { 29, 30, 31 } },
  birdRing    = { model = 34, anims = { 35, 36, 37 } },
  waves       = { model = 38, anims = { 39, 40 } },
  -- ShowLegendaryWing (overlay 2 0x0224618C): the wing over the player at
  -- the Tin Tower (0, model 55) and the Whirl Islands (1, model 65), its
  -- three animation sets from ov02_02253254 / _02253D80 / _02253D84
  wingTin          = { model = 55, anims = { 57, 56, 58 } },
  wingTinShine     = { model = 55, anims = { 59, 60, 61 } },
  wingTinFade      = { model = 55, anims = { 62, 63, 64 } },
  wingWhirl        = { model = 65, anims = { 67, 66, 68 } },
  wingWhirlShine   = { model = 65, anims = { 69, 70, 71 } },
  wingWhirlFade    = { model = 65, anims = { 72, 73, 74 } },
  -- ScrCmd_708 <n> (overlay 2 0x022460AC, table ov02_02253264): the Mahogany
  -- hideout's floor trap going off under the player -- 0 asito_thunder,
  -- 1 asito_poison, 2 asito_rock (src/world/HgssHideoutFx.lua)
  trapThunder      = { model = 10, anims = { 11 } },
  trapPoison       = { model = 3, anims = { 4, 5 } },
  trapRock         = { model = 6, anims = { 7, 8, 9 } },
  -- ScrCmd_459 (overlay 2 0x02245B80, ov02_02245D18): the Olivine
  -- Lighthouse's lamp coming back on -- model 0, animations 1 and 2, looped
  -- (src/world/HgssLighthouse.lua)
  lighthouse       = { model = 0, anims = { 1, 2 } },
  -- the Mystri Stage gymmick (src/field/gymmick/sinjoh.c
  -- SinjohGymmick_Load3dGraphics): three models 101 / 104 / 107, each with
  -- two animations (src/world/HgssSinjohStage.lua)
  sinjoh1          = { model = 101, anims = { 102, 103 } },
  sinjoh2          = { model = 104, anims = { 105, 106 } },
  sinjoh3          = { model = 107, anims = { 108, 109 } },
  -- the Sinjoh cutscenes (src/field/event_cutscene_sinjoh.c): UnownCircle's
  -- two Unown rings (79 + 80/81, 82 + 83/84) and its light (85 + 86/87);
  -- ScrCmd_817's egg, one per legend (88 / 92 / 96, each with 100 and its
  -- own BTA / BMA / BTP)
  sinjohUnown1     = { model = 79, anims = { 80, 81 } },
  sinjohUnown2     = { model = 82, anims = { 83, 84 } },
  sinjohLight      = { model = 85, anims = { 86, 87 } },
  sinjohEgg0       = { model = 88, anims = { 100, 90, 91, 89 } },
  sinjohEgg1       = { model = 92, anims = { 100, 94, 95, 93 } },
  sinjohEgg2       = { model = 96, anims = { 100, 98, 99, 97 } },
}
-- ScrCmd_709 (overlay 2 0x022462E8, ov02_02246398): the Persian statues'
-- alarm, palette 12 (0x20 bytes into BG palette 0), character data 13 and
-- screen 14 on main BG1, alpha-blended over the field
A.ALARM_PAL, A.ALARM_CHAR, A.ALARM_SCREEN = 12, 13, 14
A.LEAVES_BG2 = { 41, 42, 43, 44, 45, 46 }
A.LEAVES_BG3 = { 47, 48, 49, 50, 51, 52 }
A.LEAVES_CHAR, A.LEAVES_PAL = 53, 54
A.ALPH_PAL, A.ALPH_CHAR, A.ALPH_SCREEN = 15, 16, 17

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local arc = assert(Narc.parse(assert(x.rom:read(A.PATH))))
  local function member(i)
    local b = assert(arc:get(i))
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = { source = "ROM:" .. A.PATH .. " (pokeheartgold legend_cutscene_camera.c)", parts = {} }
  local written = {}

  local function textureImage(prefix, tex, bytes, name, paletteName)
    local key = prefix .. name .. "/" .. tostring(paletteName)
    if written[key] ~= nil then return written[key] end
    local ti, pi
    for k, t in ipairs(tex.textures) do if t.name == name then ti = k end end
    for k, p in ipairs(tex.palettes) do if p.name == paletteName then pi = k end end
    if not ti then written[key] = false return false end
    local image = Models.decode(tex, bytes, ti, pi or 1)
    local saved = image and x:saveImage(("legend/%s%s_%d"):format(prefix, name, pi or 1), image)
    written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
    return written[key]
  end

  for name, spec in pairs(A.PARTS) do
    local bytes = member(spec.model)
    local parsed = assert(Nsbmd.parse(bytes))
    local packed = Pack.pack(assert(parsed.models[1]))
    local texAt = bytes:find("TEX0", 1, true)
    local tex = texAt and Models.parse(bytes, texAt - 1)
    local prefix = ("m%d_"):format(spec.model)
    for _, shape in ipairs(packed.shapes) do
      if shape.texture and tex then
        shape.image = textureImage(prefix, tex, bytes, shape.texture, shape.palette) or nil
      end
    end
    local part = { model = packed, records = {}, frames = 0 }
    for _, m in ipairs(spec.anims) do
      local data = member(m)
      local parsed2 = Anim.parse(data)
      local animation = parsed2 and parsed2.animations and parsed2.animations[1]
      if animation then
        local frames = tonumber(animation.frames) or 0
        if frames > part.frames then part.frames = frames end
        local kind = parsed2.kind
        if kind == "BCA0" then
          local motion = { frames = frames, tracks = {} }
          for _, joint in ipairs(Anim.jointMatrices(data, animation) or {}) do
            motion.tracks[joint.index] = Anim.packTrack(joint.track)
          end
          part.motion = motion
        elseif kind == "BTA0" then
          part.records[#part.records + 1] = { kind = "BTA0", frames = frames, srt = Anim.textureSrt(data, animation) }
        elseif kind == "BTP0" then
          local pattern = Anim.texturePattern(data, animation)
          part.records[#part.records + 1] = { kind = "BTP0", frames = frames, pattern = pattern }
          -- the flipbook's pictures live in the model's own TEX0
          packed.patternImages = packed.patternImages or {}
          for i, texName in ipairs((pattern and pattern.textures) or {}) do
            if packed.patternImages[texName] == nil and tex then
              local pal = (pattern.palettes or {})[i] or (pattern.palettes or {})[1]
              packed.patternImages[texName] = textureImage(prefix, tex, bytes, texName, pal)
            end
          end
        elseif kind == "BMA0" then
          part.records[#part.records + 1] = { kind = "BMA0", frames = frames, colour = Anim.materialColour(data, animation) }
        end
      end
    end
    out.parts[name] = part
  end

  -- HeartGold's leaves: six frames of each BG layer, composed onto 256x256
  local okL, err = pcall(function()
    local tiles = assert(G.tiles(member(A.LEAVES_CHAR)))
    local palette = assert(G.palette(member(A.LEAVES_PAL)))
    out.leaves = { bg2 = {}, bg3 = {} }
    for i, m in ipairs(A.LEAVES_BG2) do
      local pic = assert(G.compose(assert(G.tilemap(member(m))), tiles, palette))
      local saved = assert(x:saveImage(("legend/leaves_bg2_%d"):format(i), pic))
      out.leaves.bg2[i] = type(saved) == "table" and saved.path or saved
    end
    for i, m in ipairs(A.LEAVES_BG3) do
      local pic = assert(G.compose(assert(G.tilemap(member(m))), tiles, palette))
      local saved = assert(x:saveImage(("legend/leaves_bg3_%d"):format(i), pic))
      out.leaves.bg3[i] = type(saved) == "table" and saved.path or saved
    end
  end)
  if not okL then out.leavesError = tostring(err) end

  -- THE RUINS OF ALPH WALL PANEL (ScrCmd_OpenAlphHiddenRoom, overlay 2
  -- 0x0224686C): palette 15, character data 16, screen 17 on main BG1; the
  -- inscription (bank 198) is printed over it in the Unown font
  local okA, errA = pcall(function()
    -- GXLoadPal(narc 15, main BG, offset 0, 0x20 bytes): the file's first
    -- sixteen colours, raw and in file order, into slot 0 -- every cell of
    -- the panel is on palette 0 (the PCMP slot table does not apply)
    local palette = assert(G.paletteAtSlot(assert(G.palette(member(A.ALPH_PAL), true)), 0))
    local pic = assert(G.compose(assert(G.tilemap(member(A.ALPH_SCREEN))), assert(G.tiles(member(A.ALPH_CHAR))), palette))
    local saved = assert(x:saveImage("legend/alph_panel", pic))
    out.alphPanel = type(saved) == "table" and saved.path or saved
  end)
  if not okA then out.alphError = tostring(errA) end

  -- THE HIDEOUT ALARM (ScrCmd_709): the same three loads the Alph panel
  -- makes -- GXLoadPal(narc 12, main BG, offset 0, 0x20 bytes) into slot 0
  local okR, errR = pcall(function()
    local palette = assert(G.paletteAtSlot(assert(G.palette(member(A.ALARM_PAL), true)), 0))
    local pic = assert(G.compose(assert(G.tilemap(member(A.ALARM_SCREEN))), assert(G.tiles(member(A.ALARM_CHAR))), palette))
    local saved = assert(x:saveImage("legend/hideout_alarm", pic))
    out.hideoutAlarm = type(saved) == "table" and saved.path or saved
  end)
  if not okR then out.alarmError = tostring(errR) end

  return out
end

return A
