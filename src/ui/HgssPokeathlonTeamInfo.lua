-- src/ui/HgssPokeathlonTeamInfo.lua -- HEARTGOLD / SOULSILVER POKeATHLON:
-- THE TEAM-CHOOSING SCREEN'S INFORMATION PANEL (pokeheartgold
-- asm/overlay_97.s). Overlay 97 is the course's first sub-overlay:
-- PokeathlonCourse_Init (src/pokeathlon/pokeathlon_course.c) opens
-- `subOverlayTemplate` = { ov97_0221E5C0, 0221E5D4, 0221E69C, OVY_97 } before
-- any event, so it runs whenever the dome's `Pokeathlon` command starts a
-- course (src/script/HgssPokeathlonCommands.lua). The picker itself (the
-- party and the PC boxes, sub_020932E0 / 02093440 in arm9) is on the touch
-- screen; overlay 97 draws the other screen, re-drawn by its callback
-- ov97_0221EC14 each time the picker's cursor lands on a Pokemon.
--
-- READ FROM CODE:
--   * the art (ov97_0221F14C / 0221F7DC): NARC 0xF3 = /a/2/4/1 palette 0,
--     char 1, screen 2 on BG3 (priority 3) and screen 3 on BG2 (priority 2);
--     the Medals are its OBJ set (char 7, palette 4, cells 6, anims 5); the
--     stars are /a/1/6/2's 0x41..0x44 -- the summary's (`gen4_hgss_summary_art`
--     perf_<c>); the Pokemon is its front picture (OBJ at (48, 72))
--   * the words, bank 278 (0221EEA4 / 0221F294 / 0221F428), in ink (1, 2) on
--     LoadFontPal0's palette: #0 the course's name (BufferPokeathlonCourseName,
--     bank 313) at (8, 8); #1 "Supreme" at (176, 8) when the course's args
--     byte 0xF is set; the nickname at (8, 120); the gender sign at (76, 120)
--     -- #2 male in (7, 8), #3 female in (3, 4), nothing for neither; the
--     labels at (104, 40 + 16 k) = #8 Speed, #4 Power, #6 Skill, #5 Stamina,
--     #7 Jump; #9 "Medals won by\n{species}" at (8, 152)
--   * the stars (0221EA88 / 0221EBD8 / 0221EDE4 -> sub_0208B85C): row r = stat r
--     (0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED, the port's order) at
--     y = 48 + 16 ov97_0221FCF4[r] {1, 3, 2, 4, 0}; star k at x 168 + 16 k
--     is hidden past the stat's maximum, empty (seq 3) past today's stars,
--     else at / above / below base (seqs 0 / 1 / 2); the Aprijuice arrow at
--     x 96 is up (seq 4) for a positive party modifier, down (5) for a
--     negative one; a party Pokemon's stars count its Aprijuice
--   * the Medals (0221ECE2 loop, PokeathlonSave_GetUnkDC_AtIndex(i, species)):
--     medal i (course i, 0..4) shown at (104 + 32 i, 168) when bit i of the
--     species' medal byte is set -- save.hgssPokeathlonMedals[species]
--     (src/pokemon/HgssPokeathlonStats.lua 021E8028)
--   * no Pokemon under the cursor (0221EFD0 / 0221F74C): the sprites and
--     BG1 / BG2 go away; the header stays
--   * the draw order: BG3, BG2, BG1 (the Pokemon's lines), the OBJs
--     (priority 1), BG0 (the header)
--
-- STAND-INS, said so:
--   * the picker: the port's party menu in its `select` mode
--     (src/ui/Gen4PartyMenu.lua), so no PC-box Pokemon (the cartridge's
--     ov97_0221E91C / 0221E97C box callbacks are not ported); this panel goes
--     on that menu's second screen, and with no second screen it shows over
--     the menu while SELECT or L is held
--   * "Supreme": the port's course has no Supreme Cup yet, so never shown
--   * the OBJ set's sequence 5 (a sparkle, created hidden at the Medals and
--     never shown by ov97) and 6 are not drawn

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")
local Strings = require("src.core.Strings")

local M = {}

M.BANK = 278
M.COURSE_BANK = 313
M.ROW_Y = { [0] = 1, 3, 2, 4, 0 }            -- ov97_0221FCF4
M.LABELS = { { 8, 40 }, { 4, 56 }, { 6, 72 }, { 5, 88 }, { 7, 104 } }
M.PERF_CELL = { [0] = 0, 1, 2 }               -- STARS_AT / ABOVE / BELOW_BASE
M.PIC_AT = { 48, 72 }

local cache = setmetatable({}, { __mode = "k" })

function M.art(game) return ((game and game.data) or {}).gen4_hgss_athlon_team end

-- an image record: a saved path (Assets) or, from a harness's ROM read, an
-- in-memory ImageData (HgssSummaryMenu:hgImg's pattern)
local function img(rec)
  if type(rec) ~= "table" then return nil end
  if cache[rec] == nil then
    local out = false
    if rec.image then
      local ok, i = pcall(love.graphics.newImage, rec.image)
      out = ok and i or false
    elseif rec.path then
      local ok, i = pcall(require("src.render.Assets").image, rec.path)
      out = ok and i or false
    end
    if out then out:setFilter("nearest", "nearest") end
    cache[rec] = out
  end
  return cache[rec] or nil, rec
end

local function sprite(rec, x, y)
  local i = img(rec)
  if not i then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(i, x + (tonumber(rec.originX) or 0), y + (tonumber(rec.originY) or 0))
end

local function line(game, n, fallback, ...)
  T.buffer(game, ...)
  local t = T.resolve(game.data, M.BANK, n, game)
  if t then t = t:gsub("{[^}]*}", "") end
  return (t and t ~= "") and t or fallback
end

local function unit(c, fb)
  c = c or fb
  return { c[1] / 255, c[2] / 255, c[3] / 255, 1 }
end

local INK_FALLBACK = { { 90, 90, 82 }, { 173, 189, 189 }, { 239, 33, 16 }, { 255, 173, 189 },
  [7] = { 0, 115, 255 }, [8] = { 123, 189, 239 } }
local function ink(game, a, b)
  local t = (M.art(game) or {}).ink or {}
  return unit(t[a], INK_FALLBACK[a]), unit(t[b], INK_FALLBACK[b])
end

local function text(game, s, x, y, a, b)
  if not s or s == "" then return end
  local fg, sh = ink(game, a or 1, b or 2)
  love.graphics.setColor(1, 1, 1, 1)
  local two = Font.beginTwoTone(fg, sh)
  if not two then love.graphics.setColor(fg) end
  local yy = y
  for l in (s .. "\n"):gmatch("(.-)\n") do
    Font.draw(l, x, yy)
    yy = yy + 16
  end
  if two then Font.endTwoTone() end
  love.graphics.setColor(1, 1, 1, 1)
end

local function speciesName(game, mon)
  local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return (def and def.name) or tostring(mon.species)
end

-- the medal byte of a species (save.hgssPokeathlonMedals, keyed by species)
function M.medalBits(save, species)
  local t = save and save.hgssPokeathlonMedals
  if type(t) ~= "table" or species == nil then return 0 end
  return tonumber(t[species] or t[tonumber(species) or species] or t[tostring(species)]) or 0
end

-- ov97_0221EC14's record for one party Pokemon: the stars' cells per row,
-- the arrows, the medals
function M.info(game, mon)
  if type(mon) ~= "table" or mon.isEgg or mon.egg then return nil end
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local juice = mon.aprijuice
  local ok, stars, colour, row = pcall(P.stars, game.data, mon, juice)
  local r = { mon = mon, rows = {}, medals = {} }
  if ok and stars and row then
    for s = 0, 4 do
      local cells = {}
      for k = 0, 4 do
        if k > (row.hi[s] or 0) then cells[k] = nil
        elseif k > (stars[s] or 0) then cells[k] = 3
        else cells[k] = M.PERF_CELL[colour[s]] or 0 end
      end
      local j = juice and tonumber(juice[s]) or 0
      r.rows[s] = { cells = cells, arrow = (j > 0 and 4) or (j < 0 and 5) or nil }
    end
  end
  local bits = M.medalBits(game.save, mon.species)
  for i = 0, 4 do r.medals[i] = math.floor(bits / 2 ^ i) % 2 == 1 end
  local okG, Pokemon = pcall(require, "src.pokemon.Pokemon")
  r.gender = okG and Pokemon.genderOf and Pokemon.genderOf(game.data, mon) or nil
  return r
end

local function picture(game, mon)
  local data = game.data
  local okS, Sprites = pcall(require, "src.pokemon.Sprites")
  if not okS then return nil end
  local path = Sprites.path(data, mon.species, "front", { mon = mon, kind = "summary" })
  if type(path) ~= "string" then return nil end
  cache.pics = cache.pics or {}
  if cache.pics[path] == nil then
    local ok, i = pcall(require("src.render.Assets").image, path)
    cache.pics[path] = ok and i or false
    if cache.pics[path] then cache.pics[path]:setFilter("nearest", "nearest") end
  end
  return cache.pics[path] or nil
end

-- the panel, 256 x 192 at (0, 0). opts: course, supreme, mon (nil = none)
function M.draw(game, opts)
  opts = opts or {}
  local g = love.graphics
  local art = M.art(game) or {}
  g.setColor(1, 1, 1, 1)
  local back = img(art.back)
  if back then g.draw(back, 0, 0) else g.setColor(0.17, 0.62, 0.6, 1); g.rectangle("fill", 0, 0, 256, 192) end
  local r = opts.mon and M.info(game, opts.mon)
  if r then
    g.setColor(1, 1, 1, 1)
    local plate = img(art.plate)
    if plate then g.draw(plate, 0, 0) end
    -- BG1: the nickname, the sign, the labels, the species line
    local mon = r.mon
    text(game, mon.nickname or speciesName(game, mon), 8, 120)
    if r.gender == "male" then text(game, line(game, 2, "♂"), 76, 120, 7, 8)
    elseif r.gender == "female" then text(game, line(game, 3, "♀"), 76, 120, 3, 4) end
    for _, l in ipairs(M.LABELS) do text(game, line(game, l[1], ""), 104, l[2]) end
    local sp = speciesName(game, mon)
    text(game, line(game, 9, Strings("Medals won by\n%s", sp), sp), 8, 152)
    -- the OBJs: the picture, the stars and arrows, the Medals
    local pic = picture(game, mon)
    if pic then
      local w, h = pic:getDimensions()
      g.setColor(1, 1, 1, 1)
      g.draw(pic, M.PIC_AT[1] - w / 2, M.PIC_AT[2] - h / 2)
    end
    local sart = ((game.data or {}).gen4_hgss_summary_art) or {}
    for s = 0, 4 do
      local row = r.rows[s]
      if row then
        local y = 48 + 16 * M.ROW_Y[s]
        for k = 0, 4 do
          if row.cells[k] then sprite(sart["perf_" .. row.cells[k]], 168 + 16 * k, y) end
        end
        if row.arrow then sprite(sart["perf_" .. row.arrow], 96, y) end
      end
    end
    for i = 0, 4 do
      if r.medals[i] then sprite(art["medal_" .. i], 104 + 32 * i, 168) end
    end
  end
  -- BG0: the header
  local course = tonumber(opts.course) or 0
  local cname = T.resolve(game.data, M.COURSE_BANK, course, game)
  cname = cname and cname:gsub("{[^}]*}", "") or ""
  T.buffer(game, cname)
  local head = T.resolve(game.data, M.BANK, 0, game)
  head = head and head:gsub("{[^}]*}", "") or ""
  text(game, head ~= "" and head or cname, 8, 8)
  if opts.supreme then text(game, line(game, 1, "Supreme"), 176, 8) end
  g.setColor(1, 1, 1, 1)
end

-- on a Gen4PartyMenu in its `select` mode: the panel follows the cursor on the
-- menu's second screen (in place of its touch balls); with no second screen
-- it covers the menu while SELECT or L is held
function M.attach(menu, game, opts)
  opts = opts or {}
  local function current()
    local party = menu.party and menu:party() or {}
    local i = tonumber(menu.index) or 0
    return party[i]
  end
  local function panel()
    M.draw(game, { course = opts.course, supreme = opts.supreme, mon = current() })
  end
  local function second()
    local ok, SS = pcall(require, "src.ui.SecondScreen")
    return ok and SS.separate(game) and not SS.stowed(game) and SS or nil
  end
  menu.hgssTeamInfo = true
  menu.drawSubscreen = function()
    local SS = second()
    if SS then SS.draw(game, panel) end
  end
  local draw = menu.draw
  menu.draw = function(self, ...)
    draw(self, ...)
    if second() then return end
    local input = game.input
    local held = input and input.isDown and (input:isDown("select") or input:isDown("l"))
    if held or menu.showTeamInfo then panel() end
  end
  return menu
end

return M
