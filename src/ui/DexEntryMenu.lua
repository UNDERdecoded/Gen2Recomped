-- Pokédex entry page: front sprite, kind, height/weight and the real
-- dex description (data/pokemon/dex_entries.asm + dex_text.asm).
--
-- `species` may be a species id string, or a table
-- `{ species = id, forceOwned = true }`.  forceOwned mirrors pret's
-- StarterDex (engine/events/starter_dex.asm), which temporarily sets the
-- owned bit so Oak's lab ball previews show height/weight/description
-- without permanently marking the mon owned.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local DexEntryMenu = {}
DexEntryMenu.__index = DexEntryMenu
DexEntryMenu.isOpaque = true

-- SGB: PalPacket_Pokedex (BROWNMON) + the mon pic zone in its palette.
-- Gen2 has no BROWNMON in its palette cache, so it borrows PREDEFPAL_POKEDEX
-- from PokedexMenu -- the two screens share _CGB_Pokedex, whose FillBoxCGB is
-- `hlcoord 1, 1 / lb bc, 7, 7`.
function DexEntryMenu:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local base = require("src.core.GameVersion").isGen2()
    and require("src.ui.PokedexMenu").GEN2_PAL
    or P.pal(game.data, "BROWNMON")
  if not base then return nil end
  local gen2 = require("src.core.GameVersion").isGen2()
  return { P.whole(base),
           P.zone(P.monPal(game.data, self.def and self.def.id), 1, 1,
                  gen2 and 7 or 8, gen2 and 7 or 8) }
end

local function resolveArgs(speciesOrOpts)
  if type(speciesOrOpts) == "table" then
    return speciesOrOpts.species or speciesOrOpts[1],
           speciesOrOpts.forceOwned and true or false
  end
  return speciesOrOpts, false
end

function DexEntryMenu.new(game, speciesOrOpts)
  local species, forceOwned = resolveArgs(speciesOrOpts)
  local self = setmetatable({ game = game, forceOwned = forceOwned }, DexEntryMenu)
  self.def = game.data.pokemon[species]
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, species, "front", { kind = "dex" })
  -- `path and pcall(...)` truncates to one value, so img was always nil and
  -- every dex page drew without its pic (#307); the guard has to be a
  -- statement for pcall's second return to survive.
  local ok, img = false, nil
  if path then ok, img = pcall(love.graphics.newImage, path) end
  self.sprite = ok and img or nil
  self.spriteTrueColor = self.sprite and trueColor or false
  require("src.core.Sound").playCry(game.data, species)
  return self
end

-- StateStack:pop calls this; the Stadium rig holds GPU buffers.
function DexEntryMenu:exit()
  require("src.render.StadiumArt").release(self.game, self)
end

function DexEntryMenu:update(dt)
  local input = self.game.input
  if not require("src.core.GameVersion").isGen2() then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
    end
    return
  end
  -- DexEntryScreen_ArrowCursorData: PAD_LEFT | PAD_RIGHT over four options
  self.cursor = self.cursor or 1
  self.page = self.page or 1
  if input:wasPressed("b") then
    self.game.stack:pop()
    return
  end
  if input:wasPressed("left") then
    self.cursor = (self.cursor - 2) % 4 + 1
  elseif input:wasPressed("right") then
    self.cursor = self.cursor % 4 + 1
  elseif input:wasPressed("a") then
    local Sound = require("src.core.Sound")
    if self.cursor == 1 then
      self.page = self.page == 1 and 2 or 1
    elseif self.cursor == 2 then
      require("src.ui.Screens").push(self.game, "TownMap",
        { nestSpecies = self.def and self.def.id })
    elseif self.cursor == 3 then
      Sound.playCry(self.game.data, self.def and self.def.id)
    else
      local Printer = require("src.core.Printer")
      Printer.save("dex_" .. tostring(self.def and self.def.id), 160, 144,
        function() DexEntryMenu.render(self.game, self.def, self.sprite, true) end)
    end
  end
end

function DexEntryMenu:draw()
  DexEntryMenu.render(self.game, self.def, self.sprite, self.forceOwned,
                      self.spriteTrueColor,
                      -- `screen` is the LIVE menu, and it is the render key
                      -- the Stadium rig is cached under.  The rest of this
                      -- table is rebuilt every frame, so keying on the table
                      -- itself meant a brand-new key per frame: the model was
                      -- thrown away and rebuilt before it could finish, every
                      -- frame, forever, and the page just kept drawing the
                      -- cartridge pic.
                      { page = self.page or 1, cursor = self.cursor or 1,
                        screen = self })
end

-- engine/pokedex/pokedex.asm Pokedex_DrawDexEntryScreenBG + pokedex_2.asm
-- DisplayDexEntry.  Pokedex_LoadGFX inverts the font and the $60-$7f block,
-- so the panel interior (tile $7f, a blank space) is palette colour 3 and
-- every glyph reads white on it; only the frame, the row-10 rule and the
-- screen margin stay on colour 2.
local GEN2_MENU = { "PAGE", "AREA", "CRY", "PRNT" }
local GEN2_MENU_X = { 16, 56, 96, 128 }

local function gen2Lines(text)
  local out = {}
  if not text then return out end
  for line in ((text:gsub("\v", "\n"):gsub("\f", "\n")) .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

local function renderGen2(game, def, sprite, forceOwned, trueColor, state)
  local page = (state and state.page) or 1
  local shade2, black, white = 0.33, 0, 1
  love.graphics.setColor(shade2, shade2, shade2, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(black, black, black, 1)
  love.graphics.rectangle("fill", 6, 6, 147, 124) -- the $7f interior
  love.graphics.rectangle("fill", 8, 136, 144, 8) -- row 17, cleared to $7f
  love.graphics.setColor(white, white, white, 1)
  love.graphics.rectangle("fill", 5, 5, 149, 1)
  love.graphics.rectangle("fill", 5, 130, 149, 1)
  love.graphics.rectangle("fill", 5, 5, 1, 126)
  love.graphics.rectangle("fill", 153, 5, 1, 126)

  -- PKMN ART = STADIUM: the player's own Stadium 2 model in the pic well,
  -- live and slowly turning.  Only on the LIVE page (`state` is the open
  -- menu): the two callers that pass no state are the Game Boy Printer, and
  -- a printout of a rotating model is not a printout of a dex entry.
  local stadium = false
  if state and state.screen then
    local StadiumArt = require("src.render.StadiumArt")
    if StadiumArt.menuMode(game) == "stadium" then
      stadium = StadiumArt.drawInto(game, state.screen, { species = def.id },
                                    8, 8, 56, 56)
    end
  end
  if sprite and not stadium then
    local w, h = sprite:getDimensions()
    local x, y = 8 + (56 - w) / 2, 8 + (56 - h) / 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sprite, x, y)
    if trueColor then
      require("src.render.PaletteFX").markTrueColor(x, y, w, h)
    end
  end

  local e = def.dexEntry or {}
  local digits = (game.data.constants or {}).dexDigits or 3
  local owned = forceOwned
    or (game.save.pokedex and game.save.pokedex.owned[def.id])
  Font.beginTint()
  love.graphics.setColor(white, white, white, 1)
  Font.draw(def.name, 72, 24)
  Font.draw(e.kind or "?", 72, 40)
  Font.draw("HT", 72, 56)
  Font.draw("WT", 72, 72)
  Font.draw(("No.%0" .. digits .. "d"):format(def.dex or 0), 16, 64)
  if owned and e.heightFt then
    Font.draw(Strings("%2d′%02d″", e.heightFt, e.heightIn or 0), 96, 56)
    local tenths = math.floor((e.weight or 0) + 0.5)
    Font.draw(Strings("%4d.%dlb", math.floor(tenths / 10), tenths % 10), 88, 72)
  end

  love.graphics.setColor(shade2, shade2, shade2, 1)
  love.graphics.rectangle("fill", 8, 85, 152, 2)
  love.graphics.setColor(black, black, black, 1)
  love.graphics.rectangle("fill", 8, 78, 16, 10)
  love.graphics.setColor(white, white, white, 1)
  Font.draw("P." .. page, 8, 80)

  local lines = owned and gen2Lines(e.text and game.data.text[e.text]) or nil
  if lines and #lines > 0 then
    for i = 1, 3 do
      local line = lines[(page - 1) * 3 + i]
      if not line then break end
      Font.draw(line, 16, 72 + i * 16)
    end
  elseif owned then
    Font.draw(Strings("Data unknown."), 16, 88)
  end

  for i, label in ipairs(GEN2_MENU) do
    Font.draw(label, GEN2_MENU_X[i], 136)
  end
  if state and state.cursor then
    Font.drawCode(0xED, GEN2_MENU_X[state.cursor] - 8, 136)
  end
  Font.endTint()
  love.graphics.setColor(1, 1, 1, 1)
end

-- Static entry-page renderer, shared with the printer stand-in
-- (src/core/Printer.lua renders the same page into a PNG the way
-- PrintPokedexEntry rendered it to the Game Boy Printer).
function DexEntryMenu.render(game, def, sprite, forceOwned, trueColor, state)
  local gen2 = require("src.core.GameVersion").isGen2()
  if gen2 then
    return renderGen2(game, def, sprite, forceOwned, trueColor, state)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if sprite then
    local y = math.max(0, 60 - sprite:getHeight())
    love.graphics.draw(sprite, 8, y)
    -- a full-color pic has to sit out the SGB recolor, so mark its bounds
    -- for the unshaded pass (#350).  The printer path leaves trueColor nil:
    -- it renders to its own PNG canvas, and a mark left behind there would
    -- bleed into the next real frame.
    if trueColor then
      require("src.render.PaletteFX").markTrueColor(8, y, sprite:getDimensions())
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
  local e = def.dexEntry or {}
  local digits = (game.data.constants or {}).dexDigits or 3
  Font.draw(def.name, 72, 8)
  -- English R/B prints only the kind string (hlcoord 9,4 PlaceString).
  -- PokeText ("#"/POKéMON) is an unreferenced JPN leftover in pokedex.asm;
  -- appending " POKéMON" here clipped longer kinds ("LIZARD POKé").
  Font.draw(e.kind or "?", 72, 20)
  -- same number width as the list (constants.dexDigits), so a dex past 999
  -- prints the extra digit everywhere at once
  Font.draw(("No.%0" .. digits .. "d"):format(def.dex or 0), 72, 32)
  local owned = forceOwned
    or (game.save.pokedex and game.save.pokedex.owned[def.id])
  -- height/weight print only once owned, like the description
  -- (pokedex.asm: "if the pokemon has not been owned, don't print the
  -- height, weight, or description")
  if owned and e.heightFt then
    -- feet/inches use the dex screen's ′/″ glyphs ("HT  ?′??″" in
    -- pokedex.asm; the tiles come from gfx/pokedex/pokedex.png via
    -- engine/gfx/load_pokedex_tiles.asm)
    if e.heightM then
      Font.draw((("GR. %.1fm"):format(e.heightM):gsub("(%d)%.(%d)", "%1,%2")), 64, 44)
      Font.draw((("GEW. %.1fkg"):format(e.weightKg or 0):gsub("(%d)%.(%d)", "%1,%2")), 64, 54)
    else
      Font.draw(Strings("HT %d′%02d″", e.heightFt, e.heightIn or 0), 72, 44)
      Font.draw(Strings("WT %.1flb", (e.weight or 0) / 10), 72, 54)
    end
  end
  local text = owned and e.text and game.data.text[e.text] or nil
  local y = 72
  if text then
    for line in (text:gsub("\v", "\n"):gsub("\f", "\n") .. "\n"):gmatch("(.-)\n") do
      if y > 132 then break end
      Font.draw(line, 8, y)
      y = y + 10
    end
  else
    Font.draw(Strings("Data unknown."), 8, y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return DexEntryMenu
