-- PLATINUM POKETCH: THE LINK SEARCHER, offline.
--
-- READ FROM CODE (pokeplatinum src/applications/poketch/link_searcher/main.c,
-- graphics.c; text bank TEXT_BANK_POKETCH_LINK_SEARCHER = 461, line 462 of
-- generated/text_banks.txt):
--   * State_OnIntroScreen: a touch on the screen starts the search
--     (Task_Searching: DS + Wi-Fi bars anim 1, "Searching for wireless..."
--     at y 16); in a Pokemon Center (MapHeader_IsPokemonCenter2, map type
--     POKECENTER) it goes to State_UnusableError instead, which waits 60
--     ticks and shows "Error!" / "Search is unusable here." (x 16, y 24) with
--     the error bubble (anim 2) and SEQ_SE_DP_BEEP
--   * State_ShowResults: waits at least 60 ticks AND for the comm system;
--     the player moving meanwhile -> State_DontMoveError ("Error!" /
--     "Please don't move while searching.", y 24, bubble, beep); results:
--     "LINK STATUS" and Union Room / Underground / Colosseum / Other Links at
--     (8, 32 + 16 i) with the count %02d at x 160 (PrintSearchResults), the
--     "connected" sprite (anim 0) at (112, 150); a touch or moving goes back
--     to the intro; the counts are re-read every 30 ticks
--   * any error screen: a touch goes back to the intro
--   * text: window BG2 (2, 2) 24 x 20 tiles, FONT_SYSTEM TEXT_COLOR(1, 8, 4);
--     the title / error lines centred on the 192-px window by their own
--     width, the multi-line blocks by their widest line; intro message y =
--     64 - lines * 8; sprites DS (112, 150) anim 3, bars (112, 102) anim 1,
--     bubble (112, 102) anim 2, connected (112, 150) anim 0
--   * sounds: SEQ_SE_DP_POKETCH_003 on intro / searching / results
-- INFERRED: there is no wireless here, so the comm system is taken to come up
-- at once and every count is 0 (what the cartridge shows with nobody near).

local M = {}

local BANK = 461
local T = { TITLE = 0, SEARCHING = 1, ERROR = 2, UNUSABLE = 3, DONT_MOVE = 4,
  STATUS = 5, UNION = 6, UNDERGROUND = 7, COLOSSEUM = 8, OTHER = 9, TOUCH = 10 }
local FALLBACK = {
  [0] = "LINK SEARCHER",
  "Searching for wireless\ncommunications activity\nPlease wait.",
  "Error!", "Search is unusable here.",
  "Please don't move\nwhile searching.",
  "LINK STATUS", "Union Room", "Underground", "Colosseum", "Other Links",
  "Touch to begin communication!",
}
local WIN_X, WIN_Y, WIN_W = 16, 16, 192
local POKECENTER = 5

local function lines(s)
  local out = {}
  s = tostring(s or ""):gsub("\r", "")
  for line in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return out
end

function M.text(watch, id)
  return watch:textBank(BANK, id, FALLBACK[id])
end

-- MapHeader_IsPokemonCenter2: the map header's type is POKECENTER.
function M.inPokemonCenter(game)
  local ow = game and game.overworld
  local def = ow and ow.map and ow.map.def
  if not def then return false end
  if tonumber(def.mapType) == POKECENTER then return true end
  local rec = game.data and game.data.gen4_area_popup
  local row = rec and rec.headers and rec.headers[tonumber(def.header) or -1]
  return row ~= nil and row.mapType == POKECENTER
end

local function playerMoving(game)
  local p = game and game.overworld and game.overworld.player
  return p ~= nil and (p.moving or p.targetX ~= nil) and true or false
end

function M.state(watch)
  watch.appState = watch.appState or {}
  local st = watch.appState.link
  if not st then
    st = { mode = "intro", timer = 0, results = { 0, 0, 0, 0 } }
    watch.appState.link = st
  end
  return st
end

-- PoketchSystem_PlaySoundEffect: Sound.playSe by SDAT name, silent while
-- the shutter is moving (as the watch's own appSe).
local function se(watch, name)
  watch.linkSe = name   -- for the test harness
  if watch.shutter then return end
  local data = watch.game and watch.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then pcall(Sound.playSe, data, name) end
end

function M.touch(watch)
  local st = M.state(watch)
  if st.mode == "intro" then
    if M.inPokemonCenter(watch.game) then
      st.mode, st.timer, st.shown = "unusable", 0, false
    else
      st.mode, st.timer = "searching", 0
    end
    se(watch, "SEQ_SE_DP_POKETCH_003")          -- Task_Searching
  elseif st.mode == "results" or st.mode == "dontmove"
      or (st.mode == "unusable" and st.shown) then
    st.mode, st.timer = "intro", 0
    se(watch, "SEQ_SE_DP_POKETCH_003")          -- Task_ShowIntroScreen
  end
end

-- One 30 Hz app tick.
function M.update(watch)
  local st = M.state(watch)
  local moving = playerMoving(watch.game)
  if st.mode == "searching" then
    if moving then
      st.mode = "dontmove"; se(watch, "SEQ_SE_DP_BEEP"); return
    end
    st.timer = math.min(60, st.timer + 1)
    if st.timer >= 60 then
      st.mode, st.timer = "results", 0
      st.results = { 0, 0, 0, 0 }
      se(watch, "SEQ_SE_DP_POKETCH_003")
    end
  elseif st.mode == "results" then
    if moving then st.mode, st.timer = "intro", 0; se(watch, "SEQ_SE_DP_POKETCH_003"); return end
    st.timer = st.timer + 1
    if st.timer >= 30 then st.timer = 0 end
  elseif st.mode == "unusable" and not st.shown then
    st.timer = st.timer + 1
    if st.timer >= 60 then st.shown = true; se(watch, "SEQ_SE_DP_BEEP") end
  end
end

local function centred(watch, s, y)
  local w = watch:lcdTextWidth(s)
  watch:lcdText(s, WIN_X + math.floor((WIN_W - w) / 2), WIN_Y + y)
end

local function block(watch, list, y)
  local w = 0
  for _, l in ipairs(list) do w = math.max(w, watch:lcdTextWidth(l)) end
  local x = WIN_X + math.floor((WIN_W - w) / 2)
  for i, l in ipairs(list) do watch:lcdText(l, x, WIN_Y + y + (i - 1) * 16) end
end

function M.draw(watch)
  local st = M.state(watch)
  local mode = st.mode
  if mode == "intro" then
    centred(watch, M.text(watch, T.TITLE), 8)
    local msg = lines(M.text(watch, T.TOUCH))
    block(watch, msg, 64 - #msg * 8)
    watch:sprite("ls_ds", "link_searcher", 3, 112, 150)
  elseif mode == "searching" or (mode == "unusable" and not st.shown) then
    block(watch, lines(M.text(watch, T.SEARCHING)), 16)
    watch:sprite("ls_ds", "link_searcher", 3, 112, 150)
    watch:sprite("ls_bars", "link_searcher", 1, 112, 102)
  elseif mode == "unusable" or mode == "dontmove" then
    centred(watch, M.text(watch, T.ERROR), 8)
    if mode == "unusable" then
      watch:lcdText(M.text(watch, T.UNUSABLE), WIN_X + 16, WIN_Y + 24)
    else
      block(watch, lines(M.text(watch, T.DONT_MOVE)), 24)
    end
    watch:sprite("ls_ds", "link_searcher", 3, 112, 150)
    watch:sprite("ls_bubble", "link_searcher", 2, 112, 102)
  elseif mode == "results" then
    centred(watch, M.text(watch, T.STATUS), 8)
    for i = 0, 3 do
      watch:lcdText(M.text(watch, T.UNION + i), WIN_X + 8, WIN_Y + 32 + 16 * i)
      watch:lcdText(("%02d"):format(st.results[i + 1] or 0), WIN_X + 160, WIN_Y + 32 + 16 * i)
    end
    watch:sprite("ls_conn", "link_searcher", 0, 112, 150)
  end
end

return M
