-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LAUNCHER'S GAME ART SCRAPER: box art and a short description for each
-- imported game, fetched only when the player asks (Settings -> GAME ART, or
-- Tools -> Scrape Game Art) and kept in the save folder.
--
--   * BOX ART from libretro-thumbnails, which names every picture after the
--     No-Intro title of the dump. The imported ROM's own file name is tried
--     first -- a No-Intro-named dump matches exactly, whatever its region --
--     then the USA / Europe titles below.
--   * THE DESCRIPTION is the lead of the game's Wikipedia article (the REST
--     summary endpoint), the first two sentences of it.

local A = {}

A.SYSTEMS = { gb = "Nintendo_-_Game_Boy", gbc = "Nintendo_-_Game_Boy_Color",
              gba = "Nintendo_-_Game_Boy_Advance", nds = "Nintendo_-_Nintendo_DS" }

A.TITLES = {
  red = { "Pokemon - Red Version (USA, Europe) (SGB Enhanced)" },
  blue = { "Pokemon - Blue Version (USA, Europe) (SGB Enhanced)" },
  yellow = { "Pokemon - Yellow Version - Special Pikachu Edition (USA, Europe) (CGB+SGB Enhanced)",
             system = "gb" },
  gold = { "Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible)" },
  silver = { "Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible)" },
  crystal = { "Pokemon - Crystal Version (USA, Europe) (Rev 1)", "Pokemon - Crystal Version (USA, Europe)" },
  firered = { "Pokemon - FireRed Version (USA, Europe) (Rev 1)", "Pokemon - FireRed Version (USA)" },
  leafgreen = { "Pokemon - LeafGreen Version (USA)", "Pokemon - LeafGreen Version (USA, Europe)" },
  emerald = { "Pokemon - Emerald Version (USA, Europe)" },
  platinum = { "Pokemon - Platinum Version (USA) (Rev 1)", "Pokemon - Platinum Version (USA)" },
  heartgold = { "Pokemon - HeartGold Version (USA)" },
  soulsilver = { "Pokemon - SoulSilver Version (USA)" },
  black = { "Pokemon - Black Version (USA, Europe) (NDSi Enhanced)" },
  white = { "Pokemon - White Version (USA, Europe) (NDSi Enhanced)" },
}

A.WIKI = {
  red = "Pokémon_Red_and_Blue", blue = "Pokémon_Red_and_Blue", yellow = "Pokémon_Yellow",
  gold = "Pokémon_Gold_and_Silver", silver = "Pokémon_Gold_and_Silver", crystal = "Pokémon_Crystal",
  firered = "Pokémon_FireRed_and_LeafGreen", leafgreen = "Pokémon_FireRed_and_LeafGreen", emerald = "Pokémon_Emerald",
  platinum = "Pokémon_Platinum", heartgold = "Pokémon_HeartGold_and_SoulSilver",
  soulsilver = "Pokémon_HeartGold_and_SoulSilver", black = "Pokémon_Black_and_White",
  white = "Pokémon_Black_and_White",
}

local function urlencode(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- libretro-thumbnails' own rule: these characters become underscores
function A.thumbName(title)
  return (tostring(title):gsub("[&%*/:`<>%?\\|\"]", "_"))
end

function A.boxartUrl(system, title)
  return ("https://raw.githubusercontent.com/libretro-thumbnails/%s/master/Named_Boxarts/%s.png")
    :format(system, urlencode(A.thumbName(title)))
end

function A.artFile(version) return ("launcher_art_%s.png"):format(version) end
function A.metaFile(version) return ("launcher_art_%s.lua"):format(version) end

-- the description saved for a version, or nil
function A.meta(version)
  local ok, chunk = pcall(love.filesystem.load, A.metaFile(version))
  if not ok or not chunk then return nil end
  local okR, t = pcall(chunk)
  return okR and type(t) == "table" and t or nil
end

local function firstSentences(text, n)
  local out, count = {}, 0
  for sentence in (tostring(text or "") .. " "):gmatch("(.-[%.!%?])%s") do
    out[#out + 1] = sentence
    count = count + 1
    if count >= n then break end
  end
  local s = table.concat(out, " ")
  return s ~= "" and s or tostring(text or "")
end

-- fetch both for one version (blocking); returns art ok, description ok
function A.scrape(version, system, romName)
  local HostShell = require("src.core.HostShell")
  if not (HostShell.canFetch and HostShell.canFetch()) then return false, false, "no network on this device" end
  local ModUpdate = require("src.mods.ModUpdate")
  local titles = {}
  if type(romName) == "string" and romName ~= "" then
    titles[#titles + 1] = romName:gsub("%.[%w]+$", "")
  end
  for _, t in ipairs(A.TITLES[version] or {}) do titles[#titles + 1] = t end
  local sys = A.SYSTEMS[(A.TITLES[version] or {}).system or system]
  local gotArt = false
  if sys then
    for _, t in ipairs(titles) do
      -- a picture left from an earlier scrape must not pass for this one
      pcall(love.filesystem.remove, A.artFile(version))
      local ok, path = pcall(ModUpdate.downloadZip, A.boxartUrl(sys, t), A.artFile(version))
      -- libretro-thumbnails stores aliases as git symlinks, which raw.github
      -- serves as the target's file name: follow one
      if ok and path then
        local body = love.filesystem.read(A.artFile(version)) or ""
        local target = #body < 300 and body:match("^%s*([^\n]-%.png)%s*$")
        if target then
          pcall(love.filesystem.remove, A.artFile(version))
          ok, path = pcall(ModUpdate.downloadZip, A.boxartUrl(sys, target:gsub("%.png$", "")), A.artFile(version))
        end
      end
      if ok and path then
        local okI = pcall(love.graphics.newImage, A.artFile(version))
        if okI then gotArt = true break end
      end
    end
  end
  local gotDesc = false
  local page = A.WIKI[version]
  if page then
    local ok, body = pcall(HostShell.httpGet, "https://en.wikipedia.org/api/rest_v1/page/summary/" .. urlencode(page),
                           "gen2recomp-launcher-art")
    if ok and type(body) == "string" then
      local okJ, Json = pcall(require, "src.link.Json")
      local okD, doc = false, nil
      if okJ then okD, doc = pcall(Json.decode, body) end
      if okD and type(doc) == "table" and type(doc.extract) == "string" then
        local Ser = require("src.core.SaveSerializer")
        local meta = { title = doc.title, description = firstSentences(doc.extract, 2),
                       source = "Wikipedia", url = doc.content_urls and doc.content_urls.desktop
                         and doc.content_urls.desktop.page, at = os.time() }
        gotDesc = love.filesystem.write(A.metaFile(version), Ser.encode(meta)) and true or false
      end
    end
  end
  return gotArt, gotDesc
end

return A
