-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LAUNCHER'S SIDEBAR: News, Games, Mods, Tools and Settings down the left,
-- with the existing panels (the game page, the mod list, Find Mods, the
-- settings rows) drawn in the content area beside it.
--
--   * GAMES walks console -> game type (series) -> the games of that pair ->
--     the game's own page (RomImporter:_drawGamePanel, unchanged). Consoles
--     with nothing imported stay on the list, dimmed, with an Import button.
--   * TOOLS lists the Map Editor, the Save Editor and the rest, then asks for
--     a game (and, for the Save Editor, a save slot) -- the same doors the
--     game page has, reachable without going through it.
--   * MODS is the installed list (now with search, tags and sort) and Find
--     Mods, as two views of one section.
--   * NEWS is where the launcher opens: a Continue card, then the latest
--     updates (the repository's own news feed when it has one, and its
--     releases).
--   * SETTINGS is the settings drawer, given the whole content area.
--
-- Installed into RomImporter by RomImporter itself (`install` at the bottom of
-- RomImporter.lua); this file only ADDS methods and wraps a few, so the classic
-- tab-bar launcher is still there behind options.launcherClassic.

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local SaveData = require("src.core.SaveData")

local Sidebar = {}

Sidebar.SECTIONS = {
  { id = "news",     label = "News" },
  { id = "games",    label = "Games" },
  { id = "walker",   label = "Monster Walker" },
  { id = "mods",     label = "Mods" },
  { id = "tools",    label = "Tools" },
  { id = "settings", label = "Settings" },
}

-- CONSOLES, derived from the game registry rather than listed per game: the
-- launcher already reads the cartridge kind off the generation (.gb / .gbc /
-- .gba / .nds), and Yellow is the one Game Boy title that ships as a .gbc.
Sidebar.CONSOLES = {
  { id = "gb",  name = "Game Boy",          short = "GB" },
  { id = "gbc", name = "Game Boy Color",    short = "GBC" },
  { id = "gba", name = "Game Boy Advance",  short = "GBA" },
  { id = "nds", name = "Nintendo DS",       short = "DS" },
}

-- The game TYPE a version belongs to. Every registered game is a Pokemon game;
-- the two community hacks are kept apart so the official games read as a set.
Sidebar.HACKS = { prism = true, polishedcrystal = true }
Sidebar.SERIES = {
  { id = "pokemon", name = "Pokemon" },
  { id = "hacks",   name = "Pokemon ROM hacks" },
}

function Sidebar.consoleOf(version)
  local info = GameVersion.info(version)
  local gen = info and tonumber(info.generation) or 1
  if gen >= 4 then return "nds" end
  if gen == 3 then return "gba" end
  if gen == 2 then return "gbc" end
  return "gb"
end

function Sidebar.seriesOf(version)
  return Sidebar.HACKS[version] and "hacks" or "pokemon"
end

function Sidebar.gamesFor(console, series)
  local out = {}
  for _, v in ipairs(GameVersion.ORDER) do
    if GameVersion.VERSIONS[v] and (console == nil or Sidebar.consoleOf(v) == console)
       and (series == nil or Sidebar.seriesOf(v) == series) then
      out[#out + 1] = v
    end
  end
  return out
end

-- a save slot's summary line, as the SAVE SLOT panel words it
local function metaText(meta)
  if type(meta) ~= "table" then return tostring(meta or "") end
  return Strings("%d badges - %s - %d caught", meta.badges or 0, meta.timeText or "0:00", meta.dexCount or 0)
end
Sidebar.metaText = metaText

local function nameOf(v)
  local info = GameVersion.info(v)
  return info and (info.displayName or info.launcherName) or tostring(v)
end
Sidebar.nameOf = nameOf

-- ---------------------------------------------------------------- options --

local function options(self) return self:_settings() end
local function saveOptions(self, opts)
  pcall(SaveData.saveOptions, opts)
  self._settingsCache = nil
end

function Sidebar.recent(opts)
  local out = {}
  for _, r in ipairs((opts and opts.launcherRecent) or {}) do
    if type(r) == "table" and GameVersion.VERSIONS[r.v] then out[#out + 1] = r end
  end
  return out
end

-- most recent first, one entry per game, six kept
function Sidebar.pushRecent(opts, version, when)
  local list = { { v = version, t = when or os.time() } }
  for _, r in ipairs(Sidebar.recent(opts)) do
    if r.v ~= version and #list < 6 then list[#list + 1] = r end
  end
  opts.launcherRecent = list
  return list
end

function Sidebar.isFavorite(opts, version)
  return type(opts and opts.launcherFavorites) == "table" and opts.launcherFavorites[version] == true
end

function Sidebar.toggleFavorite(opts, version)
  opts.launcherFavorites = type(opts.launcherFavorites) == "table" and opts.launcherFavorites or {}
  opts.launcherFavorites[version] = (not opts.launcherFavorites[version]) or nil
  return opts.launcherFavorites[version] == true
end

-- ------------------------------------------------------------ mods filter --

-- the tags a mod answers to: its category badge, the generations it supports,
-- its manifest's own `tags`, and what state it is in
function Sidebar.modTags(m)
  local tags, seen = {}, {}
  local function add(t)
    t = tostring(t or ""):upper()
    if t ~= "" and not seen[t] then seen[t] = true; tags[#tags + 1] = t end
  end
  add(m.badge)
  for g, on in pairs(m.supportedGens or {}) do
    if on == true and tonumber(g) then add("GEN " .. g) end
  end
  for _, t in ipairs(type(m.tags) == "table" and m.tags or {}) do add(t) end
  add(m.enabled and "ENABLED" or "DISABLED")
  if m.experimental then add("EXPERIMENTAL") end
  if m.updateAvailable then add("UPDATE") end
  return tags
end

Sidebar.MOD_SORTS = { "name", "order", "enabled", "updated", "category" }
Sidebar.MOD_SORT_LABELS = { name = "Name A-Z", order = "Load order", enabled = "Enabled first",
                            updated = "Recently updated", category = "Category" }

local function modTime(m)
  if m._mtime ~= nil then return m._mtime end
  local t = 0
  if type(m.manifestPath) == "string" and love and love.filesystem then
    local ok, info = pcall(love.filesystem.getInfo, m.manifestPath)
    t = ok and info and info.modtime or 0
  end
  m._mtime = t
  return t
end

function Sidebar.filterMods(mods, query, tag, sort)
  local q = tostring(query or ""):lower()
  local out = {}
  for _, m in ipairs(mods or {}) do
    local ok = true
    if q ~= "" then
      local hay = (tostring(m.name or "") .. " " .. tostring(m.id or "") .. " "
                   .. tostring(m.description or "") .. " "
                   .. table.concat(Sidebar.modTags(m), " ")):lower()
      ok = hay:find(q, 1, true) ~= nil
    end
    if ok and tag then
      ok = false
      for _, t in ipairs(Sidebar.modTags(m)) do if t == tag then ok = true break end end
    end
    if ok then out[#out + 1] = m end
  end
  local function nm(m) return tostring(m.name or m.id or ""):lower() end
  if sort == "order" then
    table.sort(out, function(a, b)
      local pa, pb = a.orderPosition or math.huge, b.orderPosition or math.huge
      if pa ~= pb then return pa < pb end
      return a.id < b.id
    end)
  elseif sort == "enabled" then
    table.sort(out, function(a, b)
      if (a.enabled and 1 or 0) ~= (b.enabled and 1 or 0) then return a.enabled == true end
      return nm(a) < nm(b)
    end)
  elseif sort == "updated" then
    table.sort(out, function(a, b)
      local ta, tb = modTime(a), modTime(b)
      if ta ~= tb then return ta > tb end
      return nm(a) < nm(b)
    end)
  elseif sort == "category" then
    table.sort(out, function(a, b)
      local ca, cb = tostring(a.badge or ""), tostring(b.badge or "")
      if ca ~= cb then return ca < cb end
      return nm(a) < nm(b)
    end)
  else
    table.sort(out, function(a, b) return nm(a) < nm(b) end)
  end
  return out
end

-- every tag any installed mod carries, for the chip row
function Sidebar.allModTags(mods)
  local seen, out = {}, {}
  for _, m in ipairs(mods or {}) do
    for _, t in ipairs(Sidebar.modTags(m)) do
      if not seen[t] then seen[t] = true; out[#out + 1] = t end
    end
  end
  table.sort(out)
  return out
end

-- ------------------------------------------------------------------- news --

Sidebar.NEWS_TTL = 6 * 60 * 60
Sidebar.NEWS_CACHE = "launcher_news.lua"

local function newsUrls()
  local repo = "UNDERdecoded/Gen2Recomped"
  local ok, Check = pcall(require, "src.update.Check")
  if ok and Check and type(Check.REPO) == "string" then repo = Check.REPO end
  return {
    feed = "https://raw.githubusercontent.com/" .. repo .. "/main/launcher_news.json",
    releases = "https://api.github.com/repos/" .. repo .. "/releases?per_page=6",
    page = "https://github.com/" .. repo .. "/releases",
  }
end
Sidebar.newsUrls = newsUrls

-- parse the repository's own feed: { "items": [ { "title", "date", "body",
-- "url" } ] } -- or a bare array of the same
function Sidebar.parseFeed(text)
  local ok, Json = pcall(require, "src.link.Json")
  if not ok then return {} end
  local okD, doc = pcall(Json.decode, text or "")
  if not okD or type(doc) ~= "table" then return {} end
  local items = doc.items or doc
  local out = {}
  for _, it in ipairs(type(items) == "table" and items or {}) do
    if type(it) == "table" and it.title then
      out[#out + 1] = { title = tostring(it.title), date = tostring(it.date or ""),
                        body = tostring(it.body or ""), url = it.url, kind = "news" }
    end
  end
  return out
end

-- the lines every release repeats (the download pointer, the contributor
-- list) say nothing about the release; what is left is its news
Sidebar.BOILERPLATE = {
  "^%s*download the correct version", "^%s*contributors%s*$", "^%s*[-*]%s*@[%w_-]+%s*$",
  "^%s*full changelog", "^%s*what'?s changed%s*$",
}
function Sidebar.trimReleaseBody(body)
  local out = {}
  for line in (tostring(body or "") .. "\n"):gmatch("(.-)\n") do
    local low, skip = line:lower(), false
    for _, pat in ipairs(Sidebar.BOILERPLATE) do if low:find(pat) then skip = true break end end
    if not skip and (line:find("%S") or (#out > 0 and out[#out]:find("%S"))) then out[#out + 1] = line end
  end
  while #out > 0 and not out[#out]:find("%S") do out[#out] = nil end
  return table.concat(out, "\n")
end

function Sidebar.parseReleases(text)
  local ok, Json = pcall(require, "src.link.Json")
  if not ok then return {} end
  local okD, doc = pcall(Json.decode, text or "")
  if not okD or type(doc) ~= "table" then return {} end
  local okU, ModUpdate = pcall(require, "src.mods.ModUpdate")
  local out = {}
  for _, r in ipairs(doc) do
    if type(r) == "table" and not r.draft then
      local body = tostring(r.body or "")
      if okU and ModUpdate.cleanBody then
        local okC, clean = pcall(ModUpdate.cleanBody, body)
        if okC and type(clean) == "string" then body = clean end
      end
      body = Sidebar.trimReleaseBody(body)
      out[#out + 1] = { title = tostring(r.name ~= "" and r.name or r.tag_name or "Release"),
                        date = tostring(r.published_at or ""):sub(1, 10),
                        body = body, url = r.html_url, kind = "release",
                        tag = r.tag_name }
    end
  end
  return out
end

local function readNewsCache()
  if not (love and love.filesystem) then return nil end
  local ok, chunk = pcall(love.filesystem.load, Sidebar.NEWS_CACHE)
  if not ok or not chunk then return nil end
  local okR, t = pcall(chunk)
  return okR and type(t) == "table" and t or nil
end

local function writeNewsCache(t)
  local ok, Ser = pcall(require, "src.core.SaveSerializer")
  if ok and love and love.filesystem then
    pcall(love.filesystem.write, Sidebar.NEWS_CACHE, "return " .. Ser.encode(t))
  end
end

-- fetch both (blocking, so it runs from update one frame after "Loading" was
-- drawn), keep whatever answered, fall back to the cache when offline
function Sidebar.fetchNews(force)
  local cache = readNewsCache()
  if not force and cache and (os.time() - (tonumber(cache.at) or 0)) < Sidebar.NEWS_TTL then
    return cache
  end
  local HostShell = require("src.core.HostShell")
  if not (HostShell.canFetch and HostShell.canFetch()) then
    return cache or { items = {}, at = 0, offline = true }
  end
  local urls = newsUrls()
  local items = {}
  local okF, feed = pcall(HostShell.httpGet, urls.feed, "gen2recomp-news")
  if okF and type(feed) == "string" then
    for _, it in ipairs(Sidebar.parseFeed(feed)) do items[#items + 1] = it end
  end
  local okR, rel = pcall(HostShell.httpGet, urls.releases, "gen2recomp-news")
  if okR and type(rel) == "string" then
    for _, it in ipairs(Sidebar.parseReleases(rel)) do items[#items + 1] = it end
  end
  if #items == 0 and cache then cache.stale = true; return cache end
  local out = { items = items, at = os.time() }
  writeNewsCache(out)
  return out
end

-- =========================================================== installation ==

function Sidebar.install(RI)
  local U = RI._ui
  local col, roundedCard, ellipsize, clamp = U.col, U.roundedCard, U.ellipsize, U.clamp
  local fillGradRounded, neonGlow = U.fillGradRounded, U.neonGlow
  local printB = U.printB
  local function PAL() return RI.palette() end
  local inside = U.inside

  -- the state the sidebar adds, after the original constructor
  local origNew = RI.new
  RI.new = function(...)
    local self = origNew(...)
    local opts = self:_settings()
    self.sidebarMode = opts.launcherClassic ~= true
    self.section = "news"
    self.gamesView = "consoles"
    self.modSort = opts.launcherModSort or "name"
    self.modSearch = ""
    -- an interrupted import belongs on its game page, where its recovery is
    if self.interruptedImport and GameVersion.VERSIONS[self.tab] then self:_sbOpenGame(self.tab) end
    self:_sbEnsureNews()
    return self
  end

  -- ------------------------------------------------------------ navigation

  function RI:_sbGo(section)
    if self.section == section and section ~= "games" and section ~= "tools" then return end
    self.section = section
    self.pageScroll = 0
    self._modSearchFocus = false
    self:_disarmTextInput()
    self.settingsOpen = (section == "settings")
    if section == "settings" then
      self.settingsScroll, self.settingsPage, self.settingsNotice = 0, nil, nil
      self._settingsRowCache = nil
    end
    if section == "games" then self.gamesView = "consoles"; self.browseConsole, self.browseSeries = nil, nil end
    if section == "tools" then self.toolFlow = nil end
    if section == "walker" then
      self.walker = self.walker or require("src.ui.PokewalkerScreen").new(self)
    end
    if section == "mods" and self.tab ~= "mods" and self.tab ~= "find" then self:_selectTab("mods") end
    if section == "news" then self:_sbEnsureNews() end
  end

  function RI:_sbOpenGame(version)
    self.section = "games"
    self.browseConsole = Sidebar.consoleOf(version)
    self.browseSeries = Sidebar.seriesOf(version)
    self.gamesView = "game"
    self.settingsOpen = false
    self:_selectTab(version)
    self.pageScroll = 0
  end

  -- one step back in whichever flow is open; false when there is nowhere to go
  function RI:_sbBack()
    if self.section == "games" then
      if self.gamesView == "game" then self.gamesView = "list"
      elseif self.gamesView == "list" then self.gamesView = "series"
      elseif self.gamesView == "series" then self.gamesView = "consoles"
      else return false end
      self.pageScroll = 0
      return true
    end
    if self.section == "tools" and self.toolFlow then
      if self.toolFlow.version and self.toolFlow.tool == "save" then self.toolFlow.version = nil
      else self.toolFlow = nil end
      self.pageScroll = 0
      return true
    end
    return false
  end

  -- the key the page scroll measures this view under
  function RI:_sbKey()
    if self.section == "games" then
      if self.gamesView == "game" then return self.tab end
      return "sb:games:" .. tostring(self.gamesView)
    end
    if self.section == "mods" then return self.tab end
    return "sb:" .. tostring(self.section)
  end

  -- -------------------------------------------------------------- layout

  -- the sidebar's width; narrow windows get an icon rail
  function RI:_sbWidth(width, s)
    if width < 760 * s then return math.floor(64 * s), true end
    return math.floor(clamp(width * 0.18, 180 * s, 240 * s)), false
  end

  local function icon(kind, cx, cy, r, s)
    local g = love.graphics
    g.setLineWidth(math.max(1, 2 * s))
    if kind == "news" then
      g.rectangle("line", cx - r, cy - r * 0.8, r * 2, r * 1.6, 2 * s, 2 * s)
      for i = 0, 2 do g.line(cx - r * 0.6, cy - r * 0.35 + i * r * 0.4, cx + r * 0.6, cy - r * 0.35 + i * r * 0.4) end
    elseif kind == "games" then
      g.rectangle("line", cx - r, cy - r * 0.6, r * 2, r * 1.2, r * 0.5, r * 0.5)
      g.line(cx - r * 0.55, cy, cx - r * 0.15, cy); g.line(cx - r * 0.35, cy - r * 0.2, cx - r * 0.35, cy + r * 0.2)
      g.circle("fill", cx + r * 0.35, cy - r * 0.1, r * 0.11); g.circle("fill", cx + r * 0.6, cy + r * 0.12, r * 0.11)
    elseif kind == "walker" then
      -- two footprints
      g.ellipse("fill", cx - r * 0.38, cy + r * 0.28, r * 0.24, r * 0.36)
      g.ellipse("fill", cx + r * 0.38, cy - r * 0.28, r * 0.24, r * 0.36)
      g.circle("fill", cx - r * 0.38, cy - r * 0.22, r * 0.1)
      g.circle("fill", cx + r * 0.38, cy - r * 0.78, r * 0.1)
    elseif kind == "mods" then
      local q = r * 0.85
      g.rectangle("line", cx - q, cy - q, q * 0.9, q * 0.9); g.rectangle("line", cx + q * 0.1, cy - q, q * 0.9, q * 0.9)
      g.rectangle("line", cx - q, cy + q * 0.1, q * 0.9, q * 0.9); g.rectangle("fill", cx + q * 0.1, cy + q * 0.1, q * 0.9, q * 0.9)
    elseif kind == "tools" then
      g.line(cx - r * 0.7, cy + r * 0.7, cx + r * 0.25, cy - r * 0.25)
      g.circle("line", cx + r * 0.45, cy - r * 0.45, r * 0.42)
    elseif kind == "settings" then
      g.circle("line", cx, cy, r * 0.62)
      for i = 0, 7 do
        local a = i * math.pi / 4
        g.line(cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62,
               cx + math.cos(a) * r, cy + math.sin(a) * r)
      end
      g.circle("line", cx, cy, r * 0.22)
    elseif kind == "speaker" or kind == "speakerOff" then
      g.polygon("fill", cx - r * 0.9, cy - r * 0.35, cx - r * 0.45, cy - r * 0.35, cx, cy - r * 0.8,
                cx, cy + r * 0.8, cx - r * 0.45, cy + r * 0.35, cx - r * 0.9, cy + r * 0.35)
      if kind == "speaker" then
        g.arc("line", "open", cx + r * 0.1, cy, r * 0.45, -0.9, 0.9)
        g.arc("line", "open", cx + r * 0.1, cy, r * 0.85, -0.9, 0.9)
      else
        g.line(cx + r * 0.25, cy - r * 0.4, cx + r * 0.95, cy + r * 0.4)
        g.line(cx + r * 0.25, cy + r * 0.4, cx + r * 0.95, cy - r * 0.4)
      end
    elseif kind == "back" then
      g.line(cx + r * 0.3, cy - r * 0.6, cx - r * 0.3, cy, cx + r * 0.3, cy + r * 0.6)
    elseif kind == "star" or kind == "starOff" then
      local pts = {}
      for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5
        local rr = (i % 2 == 0) and r or r * 0.45
        pts[#pts + 1] = cx + math.cos(a) * rr; pts[#pts + 1] = cy + math.sin(a) * rr
      end
      if kind == "star" then
        local ok = pcall(love.math.triangulate, pts)
        if ok then for _, t in ipairs(love.math.triangulate(pts)) do g.polygon("fill", t) end end
      end
      g.polygon("line", pts)
    end
    g.setLineWidth(1)
  end
  Sidebar.icon = icon

  -- the rail itself: logo, the five sections, the ready count at the foot
  function RI:_sbDrawRail(x, y, w, h, s, compact)
    local P = PAL()
    local g = love.graphics
    self._sb = { nav = {} }
    -- what is left of the window beside and under the rail: the background
    -- game is fitted to it (next frame's backdrop reads this)
    self._sbContentRect = { x = x + w, y = y, w = math.max(1, love.graphics.getWidth() - x - w), h = h }
    col(P.bgTop or P.bgBot, 0.94)
    g.rectangle("fill", x, y, w, h)
    col(P.cardBorder, 0.35)
    g.rectangle("fill", x + w - math.max(1, s), y, math.max(1, s), h)
    local cy = y + 14 * s
    local rowH = compact and 54 * s or 46 * s
    for _, sec in ipairs(Sidebar.SECTIONS) do
      local r = { x = x + 8 * s, y = cy, width = w - 16 * s, height = rowH - 6 * s, pinned = true, id = sec.id }
      local on = self.section == sec.id
      local hot = self:_hover(r)
      if on then
        fillGradRounded(r.x, r.y, r.width, r.height, 10 * s, P.link, P.link, 0.28, 0.16)
        col(P.link); g.rectangle("fill", r.x, r.y + 8 * s, 3 * s, r.height - 16 * s)
      elseif hot then
        col(P.white, 0.06); g.rectangle("fill", r.x, r.y, r.width, r.height, 10 * s, 10 * s)
      end
      col(on and P.ink or P.warning, on and 1 or 0.85)
      local ir = 10 * s
      if compact then
        icon(sec.id, r.x + r.width / 2, r.y + r.height / 2, ir, s)
      else
        icon(sec.id, r.x + 22 * s, r.y + r.height / 2, ir, s)
        g.setFont(self.tabLabelFont or self.hintFont)
        g.print(Strings(sec.label), r.x + 44 * s, r.y + (r.height - g.getFont():getHeight()) / 2)
      end
      self._sb.nav[#self._sb.nav + 1] = r
      cy = cy + rowH
    end
    self._sbRail = { x = x, y = y, w = w, h = h, compact = compact, navBottom = cy }
    -- the foot: N of X games ready
    if not compact then
      local n, total = 0, 0
      for _, v in ipairs(GameVersion.ORDER) do
        if GameVersion.VERSIONS[v] then total = total + 1; if self.ready[v] then n = n + 1 end end
      end
      g.setFont(self.readyFont or self.hintFont)
      col(P.warning, 0.8)
      g.printf(Strings("%d of %d games ready", n, total), x + 10 * s,
               y + h - g.getFont():getHeight() - 14 * s, w - 20 * s, "center")
    end
  end

  -- THE TOP BAR: the tricolour strip and the Gen 2 logo, centred across the
  -- whole window over both the rail and the content. Returns its height.
  function RI:_sbDrawTopBar(x, y, w, s, height)
    local P, g = PAL(), love.graphics
    local stripH = math.max(4, 6 * s)
    local logo = self.gen2Logo or self.logo
    local lw, lh = 1, 1
    if logo then lw, lh = logo:getDimensions() end
    local sc = math.min(math.min(w - 32 * s, 300 * s) / lw, clamp(height * 0.09, 44 * s, 86 * s) / lh)
    local barH = stripH + 10 * s + lh * sc + 10 * s
    col(P.bgTop or P.bgBot, 0.96)
    g.rectangle("fill", x, y, w, barH)
    col(P.cardBorder, 0.35)
    g.rectangle("fill", x, y + barH - math.max(1, s), w, math.max(1, s))
    local third = w / 3
    for i, c in ipairs({ P.red, P.blue, P.gold }) do
      col(c); g.rectangle("fill", x + (i - 1) * third, y, (i == 3) and (w - 2 * third) or third, stripH)
    end
    if logo then
      local pulse = self.pulse or 0
      local lx, ly = x + (w - lw * sc) / 2, y + stripH + 10 * s
      g.setBlendMode("add")
      g.setColor(1, 0.85, 0.2, 0.12 + 0.1 * (0.5 + 0.5 * math.sin(pulse * 1.6)))
      g.draw(logo, x + (w - lw * sc * 1.04) / 2, ly - lh * sc * 0.02, 0, sc * 1.04, sc * 1.04)
      g.setBlendMode("alpha")
      if self.shineShader then
        local shineW = 0.16
        self.shineShader:send("shinePos", -shineW + ((pulse % 2.8) / 2.8) * (1 + 2 * shineW))
        self.shineShader:send("shineW", shineW)
        g.setShader(self.shineShader)
      end
      g.setColor(1, 1, 1, 1)
      g.draw(logo, lx, ly, 0, sc, sc)
      g.setShader()
    end
    return barH
  end

  -- the rail's foot: the donate chip and the TiltRips code, which the classic
  -- layout keeps either side of the big logo (same rects, same handlers)
  function RI:_sbDrawRailFoot(paypalLink)
    local rail = self._sbRail
    if not rail or rail.compact then return end
    local s, P, g = self._s, PAL(), love.graphics
    local bottom = rail.y + rail.h - (self.readyFont or self.hintFont):getHeight() - 24 * s
    local x, w = rail.x + 12 * s, rail.w - 24 * s
    if paypalLink then
      local dh = self.hintFont:getHeight() + 12 * s
      local r = self:_chipButton(x, bottom - dh, paypalLink.label,
        { font = self.hintFont, w = w, h = dh, kind = "accent" })
      if r then
        r.url, r.pinned = paypalLink.url, true
        self.donateButtons = self.donateButtons or {}
        self.donateButtons[#self.donateButtons + 1] = r
        self.donateButton = r
      end
      bottom = bottom - dh - 12 * s
    end
    local logo = self.tiltRipsLogo
    if logo then
      local lw, lh = logo:getDimensions()
      local sc = math.min(w * 0.7 / lw, 40 * s / lh)
      local codeH = self.warningFont:getHeight() * 2
      local top = bottom - lh * sc - 4 * s - codeH
      if top > rail.navBottom + 10 * s then
        local lx = x + (w - lw * sc) / 2
        self.tiltRipsButton = { x = lx, y = top, width = lw * sc, height = lh * sc + 4 * s + codeH, pinned = true }
        local hot = self:_hover(self.tiltRipsButton)
        g.setColor(1, 1, 1, hot and 1 or 0.9)
        g.draw(logo, lx, top, 0, sc, sc)
        g.setFont(self.warningFont); col(P.ink)
        g.printf(Strings("Use code") .. "\nGEN2RECOMP", x, top + lh * sc + 4 * s, w, "center")
      end
    end
  end

  -- ------------------------------------------------------ the header row

  local function crumbs(self)
    if self.section == "games" then
      local out = { Strings("Games") }
      local c = self.browseConsole
      if c and self.gamesView ~= "consoles" then
        for _, row in ipairs(Sidebar.CONSOLES) do if row.id == c then out[#out + 1] = Strings(row.name) end end
      end
      if self.browseSeries and (self.gamesView == "list" or self.gamesView == "game") then
        for _, row in ipairs(Sidebar.SERIES) do if row.id == self.browseSeries then out[#out + 1] = Strings(row.name) end end
      end
      if self.gamesView == "game" then table.remove(out, 1) end
      return out
    end
    if self.section == "tools" then
      local out = { Strings("Tools") }
      local f = self.toolFlow
      if f then
        out[#out + 1] = Strings(f.label or f.tool)
        if f.version then out[#out + 1] = nameOf(f.version) end
      end
      return out
    end
    if self.section == "settings" then return {} end
    for _, sec in ipairs(Sidebar.SECTIONS) do
      if sec.id == self.section then return { Strings(sec.label) } end
    end
    return {}
  end

  -- title (breadcrumb), a back arrow when there is somewhere to go back to,
  -- and the section's own buttons on the right
  function RI:_sbDrawHeader(x, y, w, h)
    local s, P, g = self._s, PAL(), love.graphics
    self.settingsRect, self.genDropdownRect, self.romBatchRect = nil, nil, nil
    self._genMenuOpen = false
    local cx = x
    local deep = (self.section == "games" and self.gamesView ~= "consoles")
              or (self.section == "tools" and self.toolFlow ~= nil)
    if deep then
      local b = { x = x, y = y + (h - 34 * s) / 2, width = 34 * s, height = 34 * s, pinned = true }
      local hot = self:_hover(b)
      col(P.white, hot and 0.14 or 0.07)
      g.rectangle("fill", b.x, b.y, b.width, b.height, 8 * s, 8 * s)
      col(P.ink); icon("back", b.x + b.width / 2, b.y + b.height / 2, 9 * s, s)
      self._sb.back = b
      cx = x + b.width + 12 * s
    end
    -- the right-hand buttons, laid out first so the title knows its room
    local right = x + w
    local dh = math.max(30 * s, self.hintFont:getHeight() + 14 * s)
    local by = y + (h - dh) / 2
    local function chip(label, kind)
      local cw = self.hintFont:getWidth(Strings(label)) + 26 * s
      if right - cw < cx + 120 * s then return nil end
      right = right - cw
      local r = self:_chipButton(right, by, label, { w = cw, h = dh, kind = kind or "neutral" })
      if r then r.pinned = true end
      right = right - 10 * s
      return r
    end
    if self.section == "games" then
      -- on a game's page IMPORT ROMS sits on the About card instead
      if self.gamesView ~= "game" then self.romBatchRect = chip("IMPORT ROMS", "accent") end
      -- the background's music, one press away
      local on = self:_sbMusicOn()
      self._sb.music = chip("     MUSIC", on and "accent" or "neutral")
      if self._sb.music then
        col(on and P.ink or P.warning)
        icon(on and "speaker" or "speakerOff", self._sb.music.x + 17 * s,
             self._sb.music.y + self._sb.music.height / 2, 7 * s, s)
      end
      if self.gamesView == "game" and GameVersion.VERSIONS[self.tab] then
        local fav = Sidebar.isFavorite(options(self), self.tab)
        self._sb.fav = chip(fav and "     FAVORITE" or "     FAVORITE", fav and "accent" or "neutral")
        if self._sb.fav then
          self._sb.fav.version = self.tab
          col(fav and P.gold or P.warning)
          icon(fav and "star" or "starOff", self._sb.fav.x + 18 * s, self._sb.fav.y + self._sb.fav.height / 2, 7 * s, s)
        end
      end
    elseif self.section == "mods" then
      local onFind = self.tab == "find"
      self._sb.modsFind = chip("FIND MODS", onFind and "accent" or "neutral")
      self._sb.modsInstalled = chip("INSTALLED", (not onFind) and "accent" or "neutral")
    elseif self.section == "news" then
      self._sb.newsRefresh = chip("REFRESH")
    end
    -- the title / breadcrumb
    local parts = crumbs(self)
    g.setFont(self.gameNameFont)
    local text = table.concat(parts, "  ›  ")
    text = ellipsize(self.gameNameFont, text, math.max(40 * s, right - cx - 10 * s))
    col(P.ink)
    printB(text, cx, y + (h - self.gameNameFont:getHeight()) / 2)
  end

  -- ------------------------------------------------------ shared pieces

  local function card(self, x, y, w, h, dim)
    roundedCard(x, y, w, h, 14 * self._s)
    if dim then col(PAL().bgBot, 0.45); love.graphics.rectangle("fill", x, y, w, h, 14 * self._s, 14 * self._s) end
  end

  local slotCache = {}
  local function activeSlotRow(version)
    local now = love.timer and love.timer.getTime() or 0
    local hit = slotCache[version]
    if hit and now - hit.t < 2 then return hit.row end
    local row
    local ok, rows = pcall(SaveData.listSlots, version)
    if ok and type(rows) == "table" then
      local opts = SaveData.loadOptions and select(2, pcall(SaveData.loadOptions)) or nil
      local active = type(opts) == "table" and opts.saveSlots and opts.saveSlots[version]
                     and opts.saveSlots[version].active
      for _, r in ipairs(rows) do if r.id == active then row = r end end
      row = row or rows[1]
    end
    slotCache[version] = { t = now, row = row }
    return row
  end
  Sidebar.activeSlotRow = activeSlotRow

  -- a game tile: name, console, status, favourite star; returns its rect
  function RI:_sbGameTile(version, x, y, w, h)
    local s, P, g = self._s, PAL(), love.graphics
    local info = GameVersion.info(version)
    local locked = info == nil or (info.importable == false and not (U.unlockedByEnv and U.unlockedByEnv(version)))
    local ready = (not locked) and self.ready[version]
    local r = { x = x, y = y, width = w, height = h, version = version }
    local hot = self:_hover(r)
    card(self, x, y, w, h, not ready)
    if hot then col(P.white, 0.06); g.rectangle("fill", x, y, w, h, 14 * s, 14 * s) end
    -- the scraped box art, when there is any
    local art = self._sbArt and self:_sbArt(version)
    local textX = x + 14 * s
    if art then
      local aw, ah = art:getDimensions()
      local sc = math.min((h - 16 * s) / ah, (w * 0.32) / aw)
      g.setColor(1, 1, 1, ready and 1 or 0.55)
      g.draw(art, x + 8 * s, y + (h - ah * sc) / 2, 0, sc, sc)
      textX = x + 16 * s + aw * sc
    end
    g.setFont(self.stateFont or self.detailFont)
    col(P.ink, ready and 1 or 0.6)
    g.print(ellipsize(g.getFont(), nameOf(version), x + w - textX - 34 * s), textX, y + 12 * s)
    g.setFont(self.hintFont)
    local pill, pc
    if info and info.experimental and not locked then pill, pc = tostring(info.experimentalLabel or "BETA"):upper(), P.gold
    elseif ready then pill, pc = "GOOD TO GO", P.green
    elseif locked then pill, pc = "COMING SOON", P.disabledInk
    else pill, pc = "ROM REQUIRED", P.gold end
    col(pc); g.print(Strings(pill), textX, y + h - self.hintFont:getHeight() - 12 * s)
    -- the favourite star, top right
    local fav = Sidebar.isFavorite(options(self), version)
    local st = { x = x + w - 30 * s, y = y + 8 * s, width = 22 * s, height = 22 * s, version = version, star = true }
    col(fav and P.gold or P.warning, fav and 1 or 0.6)
    icon(fav and "star" or "starOff", st.x + st.width / 2, st.y + st.height / 2, 8 * s, s)
    self._sb.stars[#self._sb.stars + 1] = st
    return r
  end

  -- the imported game whose active save file was written most recently
  function RI:_sbLastSaved()
    if self._sbLastSavedAt and (love.timer.getTime() - self._sbLastSavedAt) < 5 then
      return self._sbLastSavedV
    end
    local best, bestT
    local opts = options(self)
    for _, v in ipairs(GameVersion.ORDER) do
      if self.ready[v] then
        local active = opts.saveSlots and opts.saveSlots[v] and opts.saveSlots[v].active or "slot1"
        for _, rel in ipairs({ "saves/" .. v .. "/" .. tostring(active) .. ".lua",
                               "saves/" .. v .. "/save.lua" }) do
          local ok, info = pcall(love.filesystem.getInfo, rel)
          if ok and info and info.modtime and (not bestT or info.modtime > bestT) then
            best, bestT = v, info.modtime
          end
        end
      end
    end
    self._sbLastSavedV, self._sbLastSavedAt = best, love.timer.getTime()
    return best
  end

  -- CONTINUE: the last game played and the save it will open
  function RI:_sbContinueCard(x, y, w)
    local s, P, g = self._s, PAL(), love.graphics
    local recent = Sidebar.recent(options(self))
    local v
    for _, r in ipairs(recent) do if self.ready[r.v] then v = r.v break end end
    -- nothing recorded yet (a launcher from before Recent existed): the game
    -- whose save was written last
    if not v then v = self:_sbLastSaved() end
    if not v then return 0 end
    local h = 96 * s
    card(self, x, y, w, h)
    neonGlow(x, y, w, h, 14 * s, P.playTop, 0.35)
    g.setFont(self.labelFont or self.hintFont)
    col(P.warning)
    g.print(Strings("CONTINUE"), x + 18 * s, y + 12 * s)
    g.setFont(self.gameNameFont)
    col(P.ink)
    printB(ellipsize(self.gameNameFont, nameOf(v), w * 0.6), x + 18 * s, y + 30 * s)
    local row = activeSlotRow(v)
    if row then
      g.setFont(self.hintFont)
      col(P.detail)
      local line = tostring(row.label or row.name or "") .. (row.meta and ("  ·  " .. metaText(row.meta)) or "")
      g.print(ellipsize(self.hintFont, line, w * 0.6), x + 18 * s, y + h - self.hintFont:getHeight() - 12 * s)
    end
    local label = Strings("Play %s", nameOf(v))
    local bw = math.min((self.playFont or self.gameNameFont):getWidth(label) + 64 * s, w * 0.45)
    local bh = 46 * s
    -- _playButton files its rect as playButtonRect (the game page's Play);
    -- taken off there so that handler cannot fire for this one
    self:_playButton(x + w - bw - 18 * s, y + (h - bh) / 2, bw, bh, nameOf(v), true, false)
    self._sb.continue, self.playButtonRect = self.playButtonRect, nil
    if self._sb.continue then self._sb.continue.version = v end
    return h + 16 * s
  end

  -- a row of small game chips (favourites / recent)
  function RI:_sbChipRow(title, versions, x, y, w)
    if #versions == 0 then return 0 end
    local s, P, g = self._s, PAL(), love.graphics
    g.setFont(self.labelFont or self.hintFont)
    col(P.warning)
    g.print(Strings(title), x, y)
    local cy = y + (self.labelFont or self.hintFont):getHeight() + 8 * s
    local cx = x
    local dh = math.max(30 * s, self.hintFont:getHeight() + 14 * s)
    for _, v in ipairs(versions) do
      local label = nameOf(v)
      local cw = self.hintFont:getWidth(label) + 26 * s
      if cx + cw > x + w then cx = x; cy = cy + dh + 8 * s end
      local r = self:_chipButton(cx, cy, label, { w = cw, h = dh, kind = self.ready[v] and "accent" or "neutral" })
      if r then r.version = v; self._sb.gameChips[#self._sb.gameChips + 1] = r end
      cx = cx + cw + 8 * s
    end
    return cy + dh + 18 * s - y
  end

  -- ------------------------------------------------------------- GAMES

  local function countReady(self, list)
    local n = 0
    for _, v in ipairs(list) do if self.ready[v] then n = n + 1 end end
    return n
  end

  function RI:_sbGames(x, y, w, h)
    local s, P, g = self._s, PAL(), love.graphics
    local top = y
    if self.gamesView == "consoles" then
      y = y + self:_sbContinueCard(x, y, w)
      local favs = {}
      for _, v in ipairs(GameVersion.ORDER) do
        if Sidebar.isFavorite(options(self), v) then favs[#favs + 1] = v end
      end
      y = y + self:_sbChipRow("FAVORITES", favs, x, y, w)
      local rec = {}
      for _, r in ipairs(Sidebar.recent(options(self))) do rec[#rec + 1] = r.v end
      y = y + self:_sbChipRow("RECENT", rec, x, y, w)
      g.setFont(self.labelFont or self.hintFont); col(P.warning)
      g.print(Strings("CONSOLES"), x, y)
      y = y + (self.labelFont or self.hintFont):getHeight() + 8 * s
      local cols = (w > 760 * s) and 2 or 1
      local gap = 14 * s
      local cw = (w - gap * (cols - 1)) / cols
      local ch = 112 * s
      for i, c in ipairs(Sidebar.CONSOLES) do
        local list = Sidebar.gamesFor(c.id)
        local n = countReady(self, list)
        local cx = x + ((i - 1) % cols) * (cw + gap)
        local cy = y + math.floor((i - 1) / cols) * (ch + gap)
        local r = { x = cx, y = cy, width = cw, height = ch, console = c.id }
        local hot = self:_hover(r)
        card(self, cx, cy, cw, ch, n == 0)
        if hot then col(P.white, 0.06); g.rectangle("fill", cx, cy, cw, ch, 14 * s, 14 * s) end
        g.setFont(self.gameNameFont); col(P.ink, n > 0 and 1 or 0.55)
        printB(Strings(c.name), cx + 18 * s, cy + 14 * s)
        g.setFont(self.hintFont); col(P.detail, n > 0 and 1 or 0.6)
        g.print(Strings("%d of %d games imported", n, #list), cx + 18 * s, cy + 14 * s + self.gameNameFont:getHeight() + 6 * s)
        if n == 0 then
          local lbl = "Import a ROM"
          local bw = self.hintFont:getWidth(Strings(lbl)) + 26 * s
          local ib = self:_chipButton(cx + cw - bw - 16 * s, cy + ch - 46 * s, lbl, { w = bw, kind = "accent" })
          if ib then self._sb.importButtons[#self._sb.importButtons + 1] = ib end
        end
        self._sb.consoles[#self._sb.consoles + 1] = r
      end
      y = y + math.ceil(#Sidebar.CONSOLES / cols) * (ch + gap)
      return y - top
    end
    if self.gamesView == "series" then
      local cols = (w > 760 * s) and 2 or 1
      local gap = 14 * s
      local cw = (w - gap * (cols - 1)) / cols
      local ch = 100 * s
      local i = 0
      for _, sr in ipairs(Sidebar.SERIES) do
        local list = Sidebar.gamesFor(self.browseConsole, sr.id)
        if #list > 0 then
          i = i + 1
          local n = countReady(self, list)
          local cx = x + ((i - 1) % cols) * (cw + gap)
          local cy = y + math.floor((i - 1) / cols) * (ch + gap)
          local r = { x = cx, y = cy, width = cw, height = ch, series = sr.id }
          local hot = self:_hover(r)
          card(self, cx, cy, cw, ch, n == 0)
          if hot then col(P.white, 0.06); g.rectangle("fill", cx, cy, cw, ch, 14 * s, 14 * s) end
          g.setFont(self.gameNameFont); col(P.ink, n > 0 and 1 or 0.55)
          printB(Strings(sr.name), cx + 18 * s, cy + 14 * s)
          g.setFont(self.hintFont); col(P.detail)
          g.print(Strings("%d games  ·  %d imported", #list, n), cx + 18 * s, cy + ch - self.hintFont:getHeight() - 14 * s)
          self._sb.series[#self._sb.series + 1] = r
        end
      end
      return math.ceil(i / cols) * (ch + gap)
    end
    if self.gamesView == "list" then
      local list = Sidebar.gamesFor(self.browseConsole, self.browseSeries)
      local cols = math.max(1, math.floor((w + 14 * s) / (300 * s)))
      local gap = 14 * s
      local cw = (w - gap * (cols - 1)) / cols
      local ch = 96 * s
      for i, v in ipairs(list) do
        local cx = x + ((i - 1) % cols) * (cw + gap)
        local cy = y + math.floor((i - 1) / cols) * (ch + gap)
        self._sb.tiles[#self._sb.tiles + 1] = self:_sbGameTile(v, cx, cy, cw, ch)
      end
      return math.ceil(#list / cols) * (ch + gap)
    end
    return 0
  end

  -- ------------------------------------------------------------- TOOLS

  Sidebar.TOOLS = {
    { id = "map",       label = "Map Editor",       note = "Edit an imported game's maps.", needsReady = true },
    { id = "save",      label = "Save Editor",      note = "Open a save slot in the save editor.", needsSlot = true },
    { id = "translate", label = "Translate a Game", note = "Machine-translate a game's text." },
    { id = "saveImport", label = "Import a Save",   note = "Bring in a .sav / .dsv from an emulator or cartridge." },
    { id = "saveExport", label = "Export a Save",   note = "Write the active slot out for an emulator." },
    { id = "roms",      label = "Import ROMs",      note = "Pick one or more ROM files to import.", noGame = true },
    { id = "touch",     label = "Touch Controls",   note = "Lay out the on-screen controls.", noGame = true },
    { id = "scrape",    label = "Scrape Game Art",  note = "Fetch box art and a description for a game.", needsReady = true },
    { id = "cloud",     label = "Sync Saves",       note = "Sync every imported game's saves with your cloud folder.", noGame = true },
  }

  function RI:_sbToolUsable(tool, version)
    local info = GameVersion.info(version)
    if not info then return false, "unknown game" end
    if tool.needsReady or tool.id == "translate" or tool.id == "saveExport" then
      if not self.ready[version] then return false, Strings("import this game first") end
    end
    if tool.id == "map" and not self.onEditMaps then return false, Strings("not available on this build") end
    if tool.id == "save" and not self.onEditSave then return false, Strings("not available on this build") end
    return true
  end

  function RI:_sbRunTool(tool, version, slotId)
    if tool.id == "map" then if self.onEditMaps then self.onEditMaps(version) end
    elseif tool.id == "save" then if self.onEditSave then self.onEditSave(version, slotId) end
    elseif tool.id == "translate" then
      self:_openTranslationSettings(version)
      self.section = "settings"; self.settingsOpen = true
    elseif tool.id == "saveImport" then self:chooseSaveImport(version)
    elseif tool.id == "saveExport" then self:exportSave(version)
    elseif tool.id == "roms" then self:chooseRomBatch()
    elseif tool.id == "touch" then if self.onEditTouchControls then self.onEditTouchControls() end
    elseif tool.id == "scrape" and self._sbScrape then self:_sbScrape(version)
    elseif tool.id == "cloud" then self:_sbSyncAll()
    end
  end

  -- ------------------------------------------------------------- GAME ART

  -- the scraped box art for a version (src/import/LauncherArt.lua), loaded once
  function RI:_sbArt(version)
    self._sbArtCache = self._sbArtCache or {}
    local hit = self._sbArtCache[version]
    if hit == nil then
      local Art = require("src.import.LauncherArt")
      hit = false
      if love.filesystem.getInfo(Art.artFile(version)) then
        local ok, img = pcall(love.graphics.newImage, Art.artFile(version))
        if ok and img then img:setFilter("linear", "linear"); hit = img end
      end
      self._sbArtCache[version] = hit
    end
    return hit or nil
  end

  function RI:_sbArtMeta(version)
    self._sbMetaCache = self._sbMetaCache or {}
    local hit = self._sbMetaCache[version]
    if hit == nil then
      hit = require("src.import.LauncherArt").meta(version) or false
      self._sbMetaCache[version] = hit
    end
    return hit or nil
  end

  function RI:_sbScrape(version)
    local Art = require("src.import.LauncherArt")
    local gotArt, gotDesc, why = Art.scrape(version, Sidebar.consoleOf(version), self.romName and self.romName[version])
    if self._sbArtCache then self._sbArtCache[version] = nil end
    if self._sbMetaCache then self._sbMetaCache[version] = nil end
    local name = nameOf(version)
    if why then self.settingsNotice = Strings("Could not scrape: ") .. tostring(why)
    elseif gotArt and gotDesc then self.settingsNotice = Strings("Box art and description saved for ") .. name .. "."
    elseif gotArt then self.settingsNotice = Strings("Box art saved for ") .. name .. Strings(" (no description found).")
    elseif gotDesc then self.settingsNotice = Strings("Description saved for ") .. name .. Strings(" (no box art found).")
    else self.settingsNotice = Strings("Nothing found for ") .. name .. "." end
    return gotArt, gotDesc
  end

  -- every imported game, one after the other (blocking: a few seconds each)
  function RI:_sbScrapeAll()
    local arts, descs, tried = 0, 0, 0
    for _, v in ipairs(GameVersion.ORDER or {}) do
      if self.ready[v] and Sidebar.seriesOf(v) == "pokemon" then
        tried = tried + 1
        local a, d = self:_sbScrape(v)
        if a then arts = arts + 1 end
        if d then descs = descs + 1 end
      end
    end
    if tried == 0 then self.settingsNotice = Strings("Import a game first.")
    else
      self.settingsNotice = ("%s %d/%d, %s %d/%d."):format(Strings("Box art"), arts, tried,
        Strings("descriptions"), descs, tried)
    end
  end

  -- ------------------------------------------------------------ CLOUD SAVES

  function RI:_sbCloudFolder()
    local f = options(self).cloudFolder
    return (f and f ~= "off" and f ~= "") and f or nil
  end

  -- the cloud service: "folder" (a sync folder), "google" or "onedrive"
  Sidebar.CLOUD_SERVICES = {
    google = { auth = "src.cloud.GoogleAuth", store = "src.cloud.GoogleDrive", name = "Google Drive" },
    onedrive = { auth = "src.cloud.MicrosoftAuth", store = "src.cloud.OneDrive", name = "OneDrive" },
  }
  function RI:_sbCloudService() return options(self).cloudService or "folder" end

  -- what to sync with right now: a folder path or an open store, or nil + why
  function RI:_sbCloudTarget()
    local svc = self:_sbCloudService()
    local def = Sidebar.CLOUD_SERVICES[svc]
    if not def then
      local folder = self:_sbCloudFolder()
      if not folder then return nil, Strings("Choose a sync folder in Settings -> CLOUD SAVES first.") end
      return folder
    end
    local Auth = require(def.auth)
    if not Auth.signedIn() then return nil, Strings("Sign in to ") .. def.name .. Strings(" in Settings -> CLOUD SAVES first.") end
    local store, why = require(def.store).open()
    if not store then return nil, tostring(why) end
    return store
  end

  function RI:_sbSyncSlot(version, slotId)
    local target, why0 = self:_sbCloudTarget()
    local msg
    if not target then
      msg = why0
    else
      local what, why = require("src.import.CloudSync").syncOne(target, version, slotId)
      msg = what and (Strings("Cloud sync: ") .. what) or (Strings("Cloud sync failed: ") .. tostring(why))
      self:_refreshSlots(version)
    end
    self.saveNotice = self.saveNotice or {}
    self.saveNotice[version] = { text = msg, ok = target ~= nil and msg:find("failed") == nil }
    self.settingsNotice = msg
  end

  function RI:_sbSyncAll()
    local target, why0 = self:_sbCloudTarget()
    if not target then
      self.settingsNotice = why0
      return
    end
    local list = {}
    for _, v in ipairs(GameVersion.ORDER) do if self.ready[v] then list[#list + 1] = v end end
    local C = require("src.import.CloudSync")
    local t, why = C.syncVersions(target, list)
    for _, v in ipairs(list) do pcall(self._refreshSlots, self, v) end
    self.settingsNotice = t and (Strings("Cloud sync: ") .. C.describe(t)) or (Strings("Cloud sync failed: ") .. tostring(why))
  end

  -- signing in: start the flow, show its instructions, poll it from update
  function RI:_sbCloudCancel()
    local c=self._cloudFlow
    if not c then return end
    if c.task then c.task:cancel() end
    pcall(c.auth.cancel,c.flow)
    self._cloudFlow=nil;self._settingsRowCache=nil
    self.settingsNotice=Strings('Sign-in cancelled.')
  end

  function RI:_sbCloudSignIn()
    if self._cloudFlow then self:_sbCloudCancel();return end
    local def = Sidebar.CLOUD_SERVICES[self:_sbCloudService()]
    if not def then return end
    local Auth = require(def.auth)
    local signingOut=Auth.signedIn()
    local task,why=require('src.cloud.Task').new(function()
      if signingOut then return Auth.signOut() end
      return Auth.begin()
    end)
    if not task then self.settingsNotice=tostring(why);return end
    self._cloudFlow = {auth=Auth,flow={kind='pending'},name=def.name,task=task,
      phase=signingOut and 'signOut' or 'begin',signingOut=signingOut,
      hint=Strings('Contacting the sign-in service...')}
    self._settingsRowCache = nil
    self.settingsNotice=self._cloudFlow.hint
  end

  function RI:_sbCloudInstructions(c)
    local flow=c.flow
    if flow.kind == "device" then
      -- the code popup (LauncherCloudCode) shows the code and opens the site
      self._cloudFlow.hint = ("Go to %s and enter the code  %s"):format(flow.url, flow.code)
      self.settingsNotice = ("%s: go to %s and enter the code  %s"):format(c.name, flow.url, flow.code)
    else
      self._cloudFlow.hint = Strings("Finish in your browser. If Google shows an error, press CANCEL.")
      self.settingsNotice = Strings("Finish signing in to ") .. c.name .. Strings(" in your browser...")
    end
  end

  function RI:_sbCloudPoll()
    local c = self._cloudFlow
    if not c then return end
    if not c.task then
      local now = love.timer and love.timer.getTime() or 0
      if c.flow.kind == "device" and now - (c.last or 0) < 1 then return end
      c.last=now;c.phase='poll'
      local why
      c.task,why=require('src.cloud.Task').new(function() return c.auth.poll(c.flow) end)
      if not c.task then self:_sbCloudCancel();self.settingsNotice=tostring(why);return end
    end
    local result=c.task:poll()
    if not result then return end
    c.task=nil
    if result.kind=='error' then self:_sbCloudCancel();self.settingsNotice=result.error;return end
    if c.phase=='begin' then
      if not result.first then self:_sbCloudCancel();self.settingsNotice=tostring(result.second);return end
      c.flow=result.first;self:_sbCloudInstructions(c);self._settingsRowCache=nil;return
    elseif c.phase=='signOut' then
      self._cloudFlow=nil;self._settingsRowCache=nil
      self.settingsNotice=Strings('Signed out of ')..c.name..'.';return
    end
    local state,why=result.first,result.second
    if state == "waiting" then return end
    self._cloudFlow = nil
    self._settingsRowCache = nil
    if state == "done" then
      local who = c.auth.account()
      self.settingsNotice = Strings("Signed in to ") .. c.name .. (who and (" as " .. who) or "") .. Strings(". Press SYNC NOW.")
    else
      self.settingsNotice = tostring(why)
    end
  end

  function RI:_sbTools(x, y, w, h)
    local s, P, g = self._s, PAL(), love.graphics
    local f = self.toolFlow
    local top = y
    if not f then
      local cols = math.max(1, math.floor((w + 14 * s) / (320 * s)))
      local gap = 14 * s
      local cw = (w - gap * (cols - 1)) / cols
      local ch = 92 * s
      for i, t in ipairs(Sidebar.TOOLS) do
        local cx = x + ((i - 1) % cols) * (cw + gap)
        local cy = y + math.floor((i - 1) / cols) * (ch + gap)
        local r = { x = cx, y = cy, width = cw, height = ch, tool = t }
        local hot = self:_hover(r)
        card(self, cx, cy, cw, ch)
        if hot then col(P.white, 0.06); g.rectangle("fill", cx, cy, cw, ch, 14 * s, 14 * s) end
        col(P.link); icon("tools", cx + 26 * s, cy + 30 * s, 10 * s, s)
        g.setFont(self.stateFont or self.detailFont); col(P.ink)
        g.print(Strings(t.label), cx + 48 * s, cy + 18 * s)
        g.setFont(self.hintFont); col(P.detail)
        g.printf(Strings(t.note), cx + 48 * s, cy + 18 * s + (self.stateFont or self.detailFont):getHeight() + 6 * s,
                 cw - 64 * s, "left")
        self._sb.tools[#self._sb.tools + 1] = r
      end
      return math.ceil(#Sidebar.TOOLS / cols) * (ch + gap)
    end
    -- step 2: which game
    if not f.version then
      g.setFont(self.hintFont); col(P.detail)
      g.print(Strings("Choose a game for %s", Strings(f.label)), x, y)
      y = y + self.hintFont:getHeight() + 12 * s
      local cols = math.max(1, math.floor((w + 14 * s) / (300 * s)))
      local gap = 14 * s
      local cw = (w - gap * (cols - 1)) / cols
      local ch = 76 * s
      local i = 0
      for _, v in ipairs(GameVersion.ORDER) do
        if GameVersion.VERSIONS[v] then
          i = i + 1
          local okUse, why = self:_sbToolUsable(f.tool, v)
          local cx = x + ((i - 1) % cols) * (cw + gap)
          local cy = y + math.floor((i - 1) / cols) * (ch + gap)
          local r = { x = cx, y = cy, width = cw, height = ch, version = v, usable = okUse }
          local hot = okUse and self:_hover(r)
          card(self, cx, cy, cw, ch, not okUse)
          if hot then col(P.white, 0.06); g.rectangle("fill", cx, cy, cw, ch, 14 * s, 14 * s) end
          g.setFont(self.stateFont or self.detailFont); col(P.ink, okUse and 1 or 0.55)
          g.print(ellipsize(g.getFont(), nameOf(v), cw - 28 * s), cx + 14 * s, cy + 12 * s)
          g.setFont(self.hintFont); col(okUse and P.detail or P.disabledInk)
          g.print(okUse and Strings(Sidebar.CONSOLES[({gb=1,gbc=2,gba=3,nds=4})[Sidebar.consoleOf(v)]].name) or tostring(why),
                  cx + 14 * s, cy + ch - self.hintFont:getHeight() - 12 * s)
          self._sb.toolGames[#self._sb.toolGames + 1] = r
        end
      end
      return y - top + math.ceil(i / cols) * (ch + gap)
    end
    -- step 3 (Save Editor): which slot
    local rows = {}
    local ok, list = pcall(SaveData.listSlots, f.version)
    if ok and type(list) == "table" then rows = list end
    g.setFont(self.hintFont); col(P.detail)
    g.print(Strings("Choose a save slot"), x, y)
    y = y + self.hintFont:getHeight() + 12 * s
    local rh = 64 * s
    local any = false
    for _, r in ipairs(rows) do
      if r.exists then
        any = true
        local rect = { x = x, y = y, width = w, height = rh, slot = r.id }
        local hot = self:_hover(rect)
        card(self, x, y, w, rh)
        if hot then col(P.white, 0.06); g.rectangle("fill", x, y, w, rh, 14 * s, 14 * s) end
        g.setFont(self.slotNameFont or self.detailFont); col(P.ink)
        g.print(tostring(r.label or r.name or r.id), x + 16 * s, y + 10 * s)
        g.setFont(self.hintFont); col(P.detail)
        g.print(metaText(r.meta), x + 16 * s, y + rh - self.hintFont:getHeight() - 10 * s)
        self._sb.toolSlots[#self._sb.toolSlots + 1] = rect
        y = y + rh + 10 * s
      end
    end
    if not any then
      g.setFont(self.hintFont); col(P.warning)
      g.print(Strings("This game has no saves yet."), x, y)
      y = y + self.hintFont:getHeight()
    end
    return y - top
  end

  -- -------------------------------------------------------------- NEWS

  function RI:_sbEnsureNews(force)
    if self._news and not force then return end
    self._newsPending = true
    self._newsForce = force
  end

  function RI:_sbNews(x, y, w, h)
    local s, P, g = self._s, PAL(), love.graphics
    local top = y
    y = y + self:_sbContinueCard(x, y, w)
    g.setFont(self.labelFont or self.hintFont); col(P.warning)
    g.print(Strings("LATEST UPDATES"), x, y)
    y = y + (self.labelFont or self.hintFont):getHeight() + 10 * s
    local news = self._news
    if self._newsPending or not news then
      g.setFont(self.hintFont); col(P.detail)
      g.print(Strings("Loading news..."), x, y)
      return y - top + self.hintFont:getHeight() + 10 * s
    end
    if news.offline and #(news.items or {}) == 0 then
      g.setFont(self.hintFont); col(P.detail)
      g.printf(Strings("News needs a network connection on this device."), x, y, w, "left")
      return y - top + self.hintFont:getHeight() * 2
    end
    local items = news.items or {}
    if #items == 0 then
      g.setFont(self.hintFont); col(P.detail)
      g.print(Strings("Nothing new yet."), x, y)
      return y - top + self.hintFont:getHeight() + 10 * s
    end
    for i, it in ipairs(items) do
      if i > 8 then break end
      local body = tostring(it.body or ""):gsub("\r", "")
      if it.kind == "release" then body = Sidebar.trimReleaseBody(body) end
      if #body > 700 then body = body:sub(1, 700) .. " ..." end
      local lines = {}
      if body:find("%S") then _, lines = self.hintFont:getWrap(body, w - 36 * s) end
      local nLines = math.min(#lines, 8)
      local ch = 20 * s + (self.stateFont or self.detailFont):getHeight() + 8 * s
                 + nLines * self.hintFont:getHeight() + 18 * s
      local r = { x = x, y = y, width = w, height = ch, url = it.url }
      local hot = it.url and self:_hover(r)
      card(self, x, y, w, ch)
      if hot then col(P.white, 0.05); g.rectangle("fill", x, y, w, ch, 14 * s, 14 * s) end
      g.setFont(self.stateFont or self.detailFont); col(P.ink)
      g.print(ellipsize(g.getFont(), it.title, w * 0.7), x + 18 * s, y + 16 * s)
      g.setFont(self.hintFont); col(it.kind == "news" and P.gold or P.link)
      local tagText = (it.kind == "news" and Strings("NEWS") or Strings("RELEASE")) .. (it.date ~= "" and ("  ·  " .. it.date) or "")
      g.printf(tagText, x, y + 18 * s, w - 18 * s, "right")
      col(P.detail)
      local by = y + 16 * s + (self.stateFont or self.detailFont):getHeight() + 8 * s
      for li = 1, nLines do
        g.print(lines[li], x + 18 * s, by + (li - 1) * self.hintFont:getHeight())
      end
      if it.url then self._sb.newsItems[#self._sb.newsItems + 1] = r end
      y = y + ch + 12 * s
    end
    return y - top
  end

  -- the blocking fetch, one frame after "Loading" went up
  local origUpdate = RI.update
  RI.update = function(self, dt, ...)
    if self._newsPending and self._newsDrawn then
      self._newsPending, self._newsDrawn = nil, nil
      local ok, news = pcall(Sidebar.fetchNews, self._newsForce)
      self._newsForce = nil
      self._news = ok and news or { items = {}, offline = true }
    end
    if self._newsPending then self._newsDrawn = true end
    return origUpdate(self, dt, ...)
  end

  -- ------------------------------------------------------- MODS toolbar

  local MAX_SEARCH = 40

  -- search box, tag chips and the sort button over the installed list
  function RI:_sbModToolbar(x, y, w)
    local s, P, g = self._s, PAL(), love.graphics
    self:_ensureMods()
    self._sb.modTags = {}
    local top = y
    local bh = math.max(34 * s, self.hintFont:getHeight() + 16 * s)
    -- sort button, right
    local sortLabel = Strings("Sort: %s", Strings(Sidebar.MOD_SORT_LABELS[self.modSort] or "Name A-Z"))
    local sw = self.hintFont:getWidth(sortLabel) + 26 * s
    self._sb.modSort = self:_chipButton(x + w - sw, y, sortLabel, { w = sw, h = bh })
    -- search box, the rest of the row
    local sb = { x = x, y = y, width = w - sw - 10 * s, height = bh }
    local focus = self._modSearchFocus
    col(P.slotBg or P.bgBot, 0.9)
    g.rectangle("fill", sb.x, sb.y, sb.width, sb.height, 8 * s, 8 * s)
    col(focus and P.link or P.cardBorder, focus and 0.9 or 0.45)
    g.setLineWidth(math.max(1, s)); g.rectangle("line", sb.x, sb.y, sb.width, sb.height, 8 * s, 8 * s)
    g.setFont(self.hintFont)
    local q = self.modSearch or ""
    if q == "" and not focus then
      col(P.warning, 0.7); g.print(Strings("Search mods (name, description, tag)"), sb.x + 12 * s, sb.y + (bh - self.hintFont:getHeight()) / 2)
    else
      col(P.ink)
      local caret = (focus and (math.floor((love.timer and love.timer.getTime() or 0) * 2) % 2 == 0)) and "|" or ""
      g.print(ellipsize(self.hintFont, q .. caret, sb.width - 24 * s), sb.x + 12 * s, sb.y + (bh - self.hintFont:getHeight()) / 2)
    end
    self._sb.modSearch = sb
    y = y + bh + 10 * s
    -- tag chips
    local tags = Sidebar.allModTags(self.mods or {})
    local cx = x
    local dh = math.max(26 * s, self.hintFont:getHeight() + 10 * s)
    local all = { false }
    for _, t in ipairs(tags) do all[#all + 1] = t end
    for _, t in ipairs(all) do
      local label = t or Strings("ALL")
      local cw = self.hintFont:getWidth(label) + 22 * s
      if cx + cw > x + w then cx = x; y = y + dh + 6 * s end
      local on = (t or nil) == self.modTag
      local r = self:_chipButton(cx, y, label, { w = cw, h = dh, kind = on and "accent" or "neutral" })
      if r then r.tag = t or nil; self._sb.modTags[#self._sb.modTags + 1] = r end
      cx = cx + cw + 6 * s
    end
    y = y + dh + 14 * s
    return y - top
  end

  -- ------------------------------------------------- the content dispatch

  -- true when the sidebar draws this view itself (the rest fall through to
  -- the existing panels: the game page, the mod list, Find Mods)
  function RI:_sbOwns()
    if self.section == "news" or self.section == "tools" or self.section == "settings"
       or self.section == "walker" then return true end
    if self.section == "games" and self.gamesView ~= "game" then return true end
    return false
  end

  function RI:_sbDrawContent(x, y, w, h, paged)
    self._sb.consoles, self._sb.series, self._sb.tiles, self._sb.stars = {}, {}, {}, {}
    self._sb.gameChips, self._sb.importButtons, self._sb.tools = {}, {}, {}
    self._sb.toolGames, self._sb.toolSlots, self._sb.newsItems, self._sb.modTags = {}, {}, {}, {}
    if self.section == "news" then return self:_sbNews(x, y, w, h) end
    if self.section == "games" then return self:_sbGames(x, y, w, h) end
    if self.section == "walker" and self.walker then
      return self.walker:draw(x, y, w, math.max(h, 560 * (self._s or 1)), {
        title = self.gameNameFont, head = self.stateFont or self.detailFont,
        body = self.detailFont, small = self.hintFont })
    end
    if self.section == "tools" then return self:_sbTools(x, y, w, h) end
    return 0
  end

  -- ----------------------------------------------------------- the press

  function RI:_sbMousepressed(x, y)
    local sb = self._sb
    if not sb then return false end
    for _, r in ipairs(sb.nav or {}) do
      if inside(r, x, y) then self:_sbGo(r.id); return true end
    end
    if inside(sb.back, x, y) then self:_sbBack(); return true end
    if self.section == "walker" and self.walker and self.walker:mousepressed(x, y) then return true end
    if inside(sb.fav, x, y) then
      local opts = options(self)
      Sidebar.toggleFavorite(opts, sb.fav.version); saveOptions(self, opts)
      return true
    end
    if inside(sb.music, x, y) then
      local opts = options(self)
      opts.launcherBgMusic = self:_sbMusicOn() and "off" or "on"
      saveOptions(self, opts)
      return true
    end
    if inside(sb.newsRefresh, x, y) then self._news = nil; self:_sbEnsureNews(true); return true end
    if inside(sb.modsInstalled, x, y) then self:_selectTab("mods"); return true end
    if inside(sb.modsFind, x, y) then self:_selectTab("find"); return true end
    if inside(sb.continue, x, y) then self:play(sb.continue.version); return true end
    for _, r in ipairs(sb.stars or {}) do
      if inside(r, x, y) then
        local opts = options(self)
        Sidebar.toggleFavorite(opts, r.version); saveOptions(self, opts)
        return true
      end
    end
    for _, r in ipairs(sb.gameChips or {}) do
      if inside(r, x, y) then self:_sbOpenGame(r.version); return true end
    end
    for _, r in ipairs(sb.importButtons or {}) do
      if inside(r, x, y) then self:chooseRomBatch(); return true end
    end
    for _, r in ipairs(sb.consoles or {}) do
      if inside(r, x, y) then
        self.browseConsole, self.gamesView, self.pageScroll = r.console, "series", 0
        return true
      end
    end
    for _, r in ipairs(sb.series or {}) do
      if inside(r, x, y) then
        self.browseSeries, self.gamesView, self.pageScroll = r.series, "list", 0
        return true
      end
    end
    for _, r in ipairs(sb.tiles or {}) do
      if inside(r, x, y) then self:_sbOpenGame(r.version); return true end
    end
    for _, r in ipairs(sb.tools or {}) do
      if inside(r, x, y) then
        local t = r.tool
        if t.noGame then self:_sbRunTool(t)
        else self.toolFlow = { tool = t, label = t.label }; self.pageScroll = 0 end
        return true
      end
    end
    for _, r in ipairs(sb.toolGames or {}) do
      if inside(r, x, y) then
        if r.usable then
          local f = self.toolFlow
          if f.tool.needsSlot then f.version = r.version; self.pageScroll = 0
          else self:_sbRunTool(f.tool, r.version) end
        end
        return true
      end
    end
    for _, r in ipairs(sb.toolSlots or {}) do
      if inside(r, x, y) then self:_sbRunTool(self.toolFlow.tool, self.toolFlow.version, r.slot); return true end
    end
    for _, r in ipairs(sb.newsItems or {}) do
      if inside(r, x, y) then pcall(love.system.openURL, r.url); return true end
    end
    if inside(sb.modSort, x, y) then
      local i = 1
      for k, id in ipairs(Sidebar.MOD_SORTS) do if id == self.modSort then i = k end end
      self.modSort = Sidebar.MOD_SORTS[(i % #Sidebar.MOD_SORTS) + 1]
      local opts = options(self); opts.launcherModSort = self.modSort; saveOptions(self, opts)
      return true
    end
    if inside(sb.modSearch, x, y) then
      self._modSearchFocus = true
      self:_armTextInput()
      return true
    end
    for _, r in ipairs(sb.modTags or {}) do
      if inside(r, x, y) then self.modTag = r.tag; self.pageScroll = 0; return true end
    end
    if self._modSearchFocus then self._modSearchFocus = false; self:_disarmTextInput() end
    return false
  end

  -- ----------------------------------------------- wrapped entry points

  local origPlay = RI.play
  RI.play = function(self, version, ...)
    if self.workState ~= "working" and self.ready[version] then
      -- FRESH, not the cached table: the mods panel writes options.mods
      -- through LauncherMods behind this cache's back, and saving a stale
      -- copy here put every mod switch flipped since it was read back the
      -- way it was -- Terrarium switched on, Play, and both mods ran again
      self._settingsCache = nil
      local opts = options(self)
      Sidebar.pushRecent(opts, version)
      saveOptions(self, opts)
    end
    return origPlay(self, version, ...)
  end

  local origCycle = RI._cycleTab
  RI._cycleTab = function(self, delta, ...)
    if not self.sidebarMode then return origCycle(self, delta, ...) end
    local idx = 1
    for i, sec in ipairs(Sidebar.SECTIONS) do if sec.id == self.section then idx = i end end
    idx = ((idx - 1 + delta) % #Sidebar.SECTIONS) + 1
    self:_sbGo(Sidebar.SECTIONS[idx].id)
  end

  local origText = RI.textinput
  RI.textinput = function(self, text, ...)
    if self.sidebarMode and self._modSearchFocus then
      local q = (self.modSearch or "") .. text
      if #q <= MAX_SEARCH then self.modSearch = q end
      self.pageScroll = 0
      return
    end
    return origText(self, text, ...)
  end

  local origKey = RI.keypressed
  RI.keypressed = function(self, key, ...)
    if self.sidebarMode and self.section == "walker" and self.walker and self.walker:keypressed(key) then return end
    if self.sidebarMode and self._modSearchFocus then
      if key == "backspace" then
        local q = self.modSearch or ""
        local ok, utf8 = pcall(require, "utf8")
        local off = ok and utf8.offset(q, -1) or #q
        self.modSearch = off and q:sub(1, off - 1) or ""
      elseif key == "escape" or key == "return" or key == "kpenter" then
        self._modSearchFocus = false
        self:_disarmTextInput()
      end
      return
    end
    if self.sidebarMode and key == "escape" and not (self._rename or self._indexPrompt or self._modConfirm
        or self._modVersions or self._modReleaseNotes or self._findDetails or self._genMenuOpen
        or self._findSearchFocus) then
      if self:_sbBack() then return end
    end
    -- Enter plays / imports only from a game's own page
    if self.sidebarMode and (key == "return" or key == "space" or key == "kpenter")
       and not (self.section == "games" and self.gamesView == "game") then
      return
    end
    return origKey(self, key, ...)
  end

  -- ------------------------------------------------- the live background

  local Backdrop = require("src.import.LauncherBackdrop")

  -- what the background shows now: the game being looked at, else the last
  -- one played (or the override / video / nothing the settings ask for)
  function RI:_sbBackdropWant()
    local opts = options(self)
    local mode = opts.launcherBackground or "game"
    if mode == "off" then return nil end
    if mode == "video" then return "video" end
    if GameVersion.VERSIONS[mode] then return self.ready[mode] and mode or nil end
    if mode == "game" and self.section == "games" and self.gamesView == "game"
       and self.ready[self.tab] then
      return self.tab
    end
    for _, r in ipairs(Sidebar.recent(opts)) do if self.ready[r.v] then return r.v end end
    return self:_sbLastSaved()
  end

  function RI:_sbMusicOn()
    return options(self).launcherBgMusic ~= "off"
  end

  function RI:_sbDrawBackdrop(w, h)
    local okD, drew = pcall(Backdrop.draw, w, h, self._sbContentRect)
    if okD and drew then
      -- a scrim, so the panels stay readable over a bright title screen
      col(PAL().bgBot, 0.62)
      love.graphics.rectangle("fill", 0, 0, w, h)
    end
  end

  local origUpdate2 = RI.update
  RI.update = function(self, dt, ...)
    self.sidebarMode = options(self).launcherLayout ~= "classic" and options(self).launcherClassic ~= true
    -- the Pokewalker: its screen ticks while open; otherwise the phone's
    -- steps are still collected now and then (WalkerSteps), so a walk's
    -- events reach the diary even when the screen is not up
    if self.walker and self.section == "walker" then pcall(self.walker.update, self.walker, dt)
    else
      self._walkerPumpT = (self._walkerPumpT or 0) + dt
      -- NOT for a player who never opened the Pokewalker, and never while a
      -- system picker / storage grant is in flight or Settings is up: on
      -- Android each pump is a sensor read (syncHealthSteps), which asks for
      -- ACTIVITY_RECOGNITION every time it is not granted. That runtime
      -- prompt, popping up once a minute from the launcher itself, took the
      -- place of -- and on Android 10 and older cancelled -- the storage
      -- prompt GAME DATA FOLDER's Browse needs (docs/data-location.md).
      local walkerUsed = love.filesystem.getInfo(require("src.pokewalker.Walker").FILE) ~= nil
      local busy = self.pickPending or self.section == "settings" or self.settingsOpen
      if self._walkerPumpT > 60 and (not walkerUsed or busy) then self._walkerPumpT = 0 end
      if self._walkerPumpT > 60 then
        self._walkerPumpT = 0
        pcall(function()
          local Wk = require("src.pokewalker.Walker")
          local st = Wk.load()
          local before = #st.notices
          require("src.pokewalker.WalkerSteps").pump(st, require("src.pokewalker.WalkerCourses").routes())
          local Notify = require("src.pokewalker.WalkerNotify")
          for i = before + 1, #st.notices do Notify.post(st, "Pokewalker", st.notices[i].text) end
        end)
      end
    end
    require('src.cloud.Task').reap()
    if self._cloudFlow then
      local ok,why=pcall(self._sbCloudPoll,self)
      if not ok then self:_sbCloudCancel();self.settingsNotice=Strings('Sign-in failed: ')..tostring(why) end
    end
    if self.sidebarMode and not self._handedOff then
      -- held still while Settings is open (Backdrop.setPaused)
      Backdrop.setPaused(self.section == "settings" or self.settingsOpen == true)
      Backdrop.request(self:_sbBackdropWant(), self:_sbMusicOn())
      pcall(Backdrop.update, dt, self.workState == "working")
    elseif Backdrop.current() then
      Backdrop.stop()
    end
    return origUpdate2(self, dt, ...)
  end

  -- the mount goes back before anything else takes one
  local origPlay2 = RI.play
  RI.play = function(self, version, ...)
    if self.workState ~= "working" and self.ready[version] then Backdrop.stop() end
    return origPlay2(self, version, ...)
  end
  local origNew2 = RI.new
  RI.new = function(...)
    local self = origNew2(...)
    for _, key in ipairs({ "onEditSave", "onEditMaps", "onEditTouchControls" }) do
      local fn = self[key]
      if fn then self[key] = function(...) Backdrop.stop(); return fn(...) end end
    end
    return self
  end
  local origChoose = RI.choose
  RI.choose = function(self, ...) Backdrop.stop(); return origChoose(self, ...) end
  local origBatch = RI.chooseRomBatch
  RI.chooseRomBatch = function(self, ...) Backdrop.stop(); return origBatch(self, ...) end

  -- THE SETTINGS PAGE, full height: everything right of the rail and under
  -- the top bar, drawn last so the footer does not sit over it
  local origDraw = RI.draw
  RI.draw = function(self, ...)
    local r = origDraw(self, ...)
    if not (self.sidebarMode and self.section == "settings" and self.settingsOpen) then return r end
    local area = self._sbContentRect
    if not area then return r end
    local s, g = self._s or 1, love.graphics
    local pad = 16 * s
    local dx, dy, dw, dh = area.x, area.y, area.w, area.h
    self.settingsDrawerRect = { x = dx, y = dy, width = dw, height = dh, pinned = true }
    g.push("all")
    g.origin()
    col(PAL().bgTop or PAL().bgBot, 1)
    g.rectangle("fill", dx, dy, dw, dh)
    local prevBand = U.setPageBand and U.setPageBand(nil)
    g.setScissor(math.floor(dx), math.floor(dy), math.ceil(dw), math.ceil(dh))
    local maxW = math.min(dw - 2 * pad, 1100 * s)
    local px = dx + (dw - maxW) / 2
    local natural = self:_drawSettingsPanel(px, dy + pad - (self.settingsScroll or 0), maxW, dh, false) or 0
    g.setScissor()
    if U.setPageBand then U.setPageBand(prevBand) end
    g.pop()
    for _, row in ipairs(self.settingsRowRects or {}) do
      for _, part in pairs(row) do
        if type(part) == "table" and part.width then
          part.pinned = true
          part.clipY = { dy, dy + dh }
        end
      end
    end
    self._settingsMax = math.max(0, natural + 2 * pad - dh)
    return r
  end

  -- --------------------------------------------- the launcher settings rows

  -- THE CLOUD SAVES ROWS, at the top of the main Settings page: the service,
  -- its account (or its sync folder), SYNC NOW
  function RI:_sbCloudRows(add)
      -- CLOUD SAVES (src/import/CloudSync.lua): a sync folder on this machine
      self._cloudFolders = self._cloudFolders or require("src.import.CloudSync").detectFolders()
      local cfValues, cfLabels = { "off" }, { off = "Off" }
      for _, f in ipairs(self._cloudFolders) do
        if not cfLabels[f.path] then cfValues[#cfValues + 1] = f.path; cfLabels[f.path] = f.name .. "  " .. f.path end
      end
      local cur = options(self).cloudFolder
      if cur and cur ~= "off" and not cfLabels[cur] then cfValues[#cfValues + 1] = cur; cfLabels[cur] = "Folder  " .. cur end
      add({ kind = "section", label = "CLOUD SAVES",
            note = "Sync your saves with Google Drive, OneDrive, or a sync folder on this computer (Dropbox, iCloud...). A save is never replaced on its first sync; two backups are kept on each side." })
      add({ kind = "option", scope = "launcher", label = "SERVICE",
            row = { id = "cloudService", values = { "folder", "google", "onedrive" },
                    labels = { folder = "Sync folder", google = "Google Drive", onedrive = "OneDrive" } } })
      local svcDef = Sidebar.CLOUD_SERVICES[self:_sbCloudService()]
      if svcDef then
        local Auth = require(svcDef.auth)
        local who = Auth.signedIn() and (Auth.account() or "signed in") or nil
        add({ kind = "action", label = who and ("ACCOUNT  " .. who) or "ACCOUNT",
              value = self._cloudFlow and "CANCEL" or (who and "SIGN OUT" or "SIGN IN"), action = "sbCloudSignIn",
              note = self._cloudFlow and self._cloudFlow.hint or nil })
      else
        add({ kind = "option", scope = "launcher", label = "SYNC FOLDER",
              row = { id = "cloudFolder", values = cfValues, labels = cfLabels } })
        add({ kind = "action", label = "OTHER FOLDER", value = "BROWSE", action = "sbCloudBrowse" })
      end
      add({ kind = "action", label = "SYNC ALL SAVES", value = "SYNC NOW", action = "sbCloudSyncAll" })
  end

  Sidebar.DEFAULTS = { launcherLayout = "sidebar", launcherBackground = "game", launcherBgMusic = "on",
                       cloudFolder = "off", cloudService = "folder" }

  local origRows = RI._launcherSettingsRows
  RI._launcherSettingsRows = function(self, ...)
    local rows = origRows(self, ...)
    local function add(r) rows[#rows + 1] = r end
    add({ kind = "section", label = "LAUNCHER LAYOUT",
          note = "The sidebar (News, Games, Mods, Tools, Settings) or the classic row of game chips." })
    add({ kind = "option", scope = "launcher", label = "LAYOUT",
          row = { id = "launcherLayout", values = { "sidebar", "classic" },
                  labels = { sidebar = "Sidebar", classic = "Classic" } } })
    local bgValues = { "game", "last", "off", "video" }
    local bgLabels = { game = "The game you're viewing", last = "Last game played", off = "None",
                       video = "Custom video" }
    -- only games that are imported and can actually run their menu
    for _, v in ipairs(GameVersion.ORDER) do
      local info = GameVersion.info(v)
      if self.ready[v] == true and info and info.importable ~= false and not Backdrop.failedFor(v) then
        bgValues[#bgValues + 1] = v; bgLabels[v] = nameOf(v)
      end
    end
    add({ kind = "section", label = "BACKGROUND",
          note = "Behind the launcher: an imported game's own main menu, a video of your own (.ogv), or nothing." })
    add({ kind = "option", scope = "launcher", label = "BACKGROUND",
          row = { id = "launcherBackground", values = bgValues, labels = bgLabels } })
    add({ kind = "option", scope = "launcher", label = "BACKGROUND MUSIC",
          row = { id = "launcherBgMusic", values = { "on", "off" }, labels = { on = "On", off = "Off" } } })
    add({ kind = "action", label = "CUSTOM VIDEO", value = "CHOOSE .OGV", action = "sbChooseVideo" })
    add({ kind = "section", label = "GAME ART",
          note = "Box art and a short description for each imported game, fetched from libretro-thumbnails and Wikipedia." })
    add({ kind = "action", label = "SCRAPE ART & DESCRIPTIONS", value = "START", action = "sbScrapeAll" })
    return rows
  end

  local origSettingsRows = RI._settingsRows
  RI._settingsRows = function(self, ...)
    local rows = origSettingsRows(self, ...)
    if not self.sidebarMode or self.settingsPage ~= nil then return rows end
    local top = {}
    pcall(self._sbCloudRows, self, function(r) top[#top + 1] = r; return r end)
    for i = #top, 1, -1 do table.insert(rows, 1, top[i]) end
    return rows
  end

  -- a SERVICE / SYNC FOLDER change re-lays the section at once (and a
  -- service change drops a sign-in that was waiting on the old one)
  local origSetValue = RI._setSettingValue
  RI._setSettingValue = function(self, entry, value, ...)
    local r = origSetValue(self, entry, value, ...)
    local id = entry and entry.row and entry.row.id
    if id == "cloudService" or id == "cloudFolder" then
      if id == "cloudService" and self._cloudFlow then
        self:_sbCloudCancel()
      end
      pcall(function() saveOptions(self, options(self)) end)
      self._settingsRowCache = nil
    end
    return r
  end

  local origValue = RI._settingValue
  RI._settingValue = function(self, entry, ...)
    local id = entry and entry.row and entry.row.id
    if entry and entry.scope == "launcher" and Sidebar.DEFAULTS[id] then
      local v = options(self)[id]
      if v == nil or v == false then return Sidebar.DEFAULTS[id] end
      return v
    end
    return origValue(self, entry, ...)
  end

  local origAction = RI._settingsAction
  RI._settingsAction = function(self, entry, ...)
    local action = entry and entry.action
    if action == "sbChooseVideo" then
      local path = U.chooseFileByExt and U.chooseFileByExt({ "ogv" }, "background video (.ogv)")
      if path then
        local f = io.open(path, "rb")
        local data = f and f:read("*a")
        if f then f:close() end
        if data and love.filesystem.write(Backdrop.VIDEO_FILE, data) then
          local opts = options(self)
          opts.launcherBackground = "video"
          saveOptions(self, opts)
          Backdrop._state.failed.video = nil
          self.settingsNotice = Strings("Background video set.")
        else
          self.settingsNotice = Strings("Could not read that video.")
        end
      end
      return
    elseif action == "sbCloudBrowse" then
      local path = U.chooseFolder and U.chooseFolder(Strings("Choose your cloud sync folder"))
      if path and path ~= "" then
        local opts = options(self)
        opts.cloudFolder = path
        saveOptions(self, opts)
        self.settingsNotice = Strings("Sync folder set.")
      end
      return
    elseif action == "sbCloudSignIn" then
      self:_sbCloudSignIn()
      return
    elseif action == "sbCloudSyncAll" then
      self:_sbSyncAll()
      return
    elseif action == "sbScrapeAll" then
      if self._sbScrapeAll then self:_sbScrapeAll() end
      return
    end
    return origAction(self, entry, ...)
  end

  -- THE ABOUT CARD over a game's page: its scraped box art and description,
  -- with the game's Import / Re-import ROM button bottom right
  local origGamePanel = RI._drawGamePanel
  RI._drawGamePanel = function(self, version, x, y, w, h, paged)
    if not (self.sidebarMode and self.section == "games") then
      return origGamePanel(self, version, x, y, w, h, paged)
    end
    local art, meta = self:_sbArt(version), self:_sbArtMeta(version)
    local s, P, g = self._s, PAL(), love.graphics
    local pad = 16 * s
    local artH = art and math.min(150 * s, w * 0.3) or 0
    local artW = art and artH * art:getWidth() / art:getHeight() or 0
    local textX = x + pad + (art and (artW + pad) or 0)
    local textW = x + w - pad - textX
    local lines = {}
    if meta and meta.description then _, lines = self.hintFont:getWrap(meta.description, textW) end
    local nLines = math.min(#lines, 7)
    local titleH = (self.stateFont or self.detailFont):getHeight()
    local btnH = math.max(36 * s, self.saveBtnFont:getHeight() + 18 * s)
    local textH = titleH + 8 * s + nLines * self.hintFont:getHeight()
                  + (meta and meta.source and (self.hintFont:getHeight() + 6 * s) or 0)
    local ch = math.max(artH, textH + 14 * s + btnH) + pad * 2
    -- the panel first: it decides the game's import button (self._sbRomBtn)
    local gap = 14 * s
    local rest = origGamePanel(self, version, x, y + ch + gap, w, math.max(0, h - ch - gap), paged) or 0
    card(self, x, y, w, ch)
    if art then
      g.setColor(1, 1, 1, 1)
      g.draw(art, x + pad, y + (ch - artH) / 2, 0, artH / art:getHeight(), artH / art:getHeight())
    end
    local ty = y + pad
    g.setFont(self.stateFont or self.detailFont); col(P.ink)
    g.print(ellipsize(g.getFont(), (meta and meta.title) or nameOf(version), textW), textX, ty)
    ty = ty + titleH + 8 * s
    g.setFont(self.hintFont); col(P.detail)
    for li = 1, nLines do g.print(lines[li], textX, ty + (li - 1) * self.hintFont:getHeight()) end
    if meta and meta.source then
      col(P.detail, 0.6)
      g.print(Strings("From ") .. tostring(meta.source), textX, ty + nLines * self.hintFont:getHeight() + 6 * s)
    end
    -- bottom right: the one import button -- "Import ROM" until the game is
    -- in, "Re-import ROM" after (the panel picks the label)
    local rb = self._sbRomBtn
    if rb and rb.label then
      local bw = math.max(150 * s, self.saveBtnFont:getWidth(Strings(rb.label)) + 40 * s)
      self.romButtonRect = self:_glassyButton(x + w - pad - bw, y + ch - pad - btnH, bw, btnH,
                                              rb.label, self.saveBtnFont, rb.enabled)
    end
    return ch + gap + rest
  end

  local origTranslate = RI._openTranslationSettings
  RI._openTranslationSettings = function(self, ...)
    local r = origTranslate(self, ...)
    if self.sidebarMode then self.section = "settings"; self.settingsOpen = true end
    return r
  end

  -- the sign-in code popup, over everything (installed last: drawn last,
  -- pressed first)
  require("src.import.LauncherCloudCode").install(RI)
end

return Sidebar
