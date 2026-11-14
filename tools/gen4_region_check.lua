-- tools/gen4_region_check.lua -- does a localized Platinum import hold the
-- SAME GAME as the US one?
--
--   python tools/run_lua_check.py tools/gen4_region_check.lua <us cache> <other cache> [verbose]
--
-- Each cache is a version folder (…/platinum, holding data/generated).  Every
-- generated table is loaded from both and walked side by side.  A difference
-- is sorted into one of three bins:
--
--   TEXT    both values are strings and the key is one the cartridge's
--           language decides (a name, a description, a label, a line of
--           dialogue -- TEXT_KEYS below), or the whole table is text
--           (TEXT_FILES).  Expected: a German cartridge says it in German.
--   KNOWN   a difference the cartridges really have, listed in KNOWN below
--           with the reason (the European bug fixes, the German build's
--           localized art).  Reported, not failed.
--   DATA    anything else.  A number, a flag, a table shape or a non-text
--           string that is not the same is the extractor reading something
--           else on the other cartridge -- which is exactly the silent
--           wrong-address failure this check exists to catch.  Any DATA
--           difference fails the run.
--
-- Asset PATHS are compared after folding the name part out of a
-- "NNN_name" file stem, so "battle/front/001_bulbasaur" on the US cartridge
-- and "battle/front/001" on a German one compare equal: the file is chosen
-- by id, the name was only ever a label for a human.

local usDir, otherDir, verbose = arg[1], arg[2], arg[3]
assert(usDir and otherDir, "usage: gen4_region_check.lua <us cache> <other cache> [verbose]")

-- tables that are nothing but the cartridge's text
local TEXT_FILES = { ["text.lua"] = true, ["gen4_text.lua"] = true, ["text_pointers.lua"] = true }

-- keys whose string value is the cartridge's language
local TEXT_KEYS = {}
for k in ([[name names label labels description descriptions text texts title
  dexEntry entry category categoryName height weight heightText weightText line lines
  message messages className classArticle article nickname otName trainerName
  words word caption captions prompt prompts question answer answers option options
  string strings menu menus hint hints rank ranks greeting farewell win lose
  firstLine noun plural singular pocket pockets displayName shortName longName
  mapName areaName location locationName placeName place town route sign
  speciesName moveName itemName abilityName natureName typeName]]):gmatch("%S+") do
  TEXT_KEYS[k] = true
end

-- keys whose value is WHERE something was found (an ARM9/overlay offset, a
-- RAM address, a "ROM:overlay5+0x2B414" provenance line).  The German build
-- is a different link of the same code, so these move while what they point
-- at stays the same -- which the rest of the table proves.
local ADDRESS_KEYS = { at = true, source = true, paletteTable = true, overlayRam = true }

-- keys holding prose the cartridge's language decides, beyond TEXT_KEYS
for k in ("controlInfo adventureInfo offer intro choose natures types characteristics newGameWarning order"):gmatch("%S+") do
  TEXT_KEYS[k] = true
end

-- Differences the cartridges themselves carry, by file and path prefix
-- (docs/rom-revisions.md, "Platinum (Europe) and (Germany)").
local KNOWN = {
  -- (Europe) and (Germany) both: land_data member 164 (Route 225) differs in
  -- four collision bytes
  { file = "gen4_map_permissions.lua", path = "[164]", why = "Route 225 collision (EU/DE cartridges)" },
  { file = "map_layouts.lua", path = "[0].blocks", why = "Route 225 collision (EU/DE cartridges)" },
  { file = "maps.lua", path = ".R225.blocks", why = "Route 225 collision (EU/DE cartridges)" },
  -- script files differ: 141 (Veilstone Game Corner) on both, and on the
  -- German cartridge also 31, 148, 367, 376..379 and 500
  { file = "map_scripts.lua", why = "script files the EU/DE cartridges rewrote" },
  -- the slot machine's art differs on European cartridges, and the German
  -- one draws a wider "games" label
  { file = "gen4_pt_slot_art.lua", why = "slot machine art (EU/DE cartridges)" },
  -- German build: the Pokedex's A-Z order and its by-initial search groups
  -- (ABC, DEF, ...) follow the German names (zukan_data.narc 13, 18..26)
  { file = "gen4_dex.lua", why = "German alphabetical order and initial groups",
    test = function(path)
      local key = path:match("^%.orders%.(%a+)%[")
      return key == "alphabetical" or key == "ABC" or key == "DEF" or key == "GHI"
          or key == "JKL" or key == "MNO" or key == "PQR" or key == "STU"
          or key == "VWX" or key == "YZ"
    end },
  -- German build: the in-game trades' Pokemon come from other languages
  { file = "constants.lua", why = "in-game trade language (a German cartridge's trades are foreign)",
    test = function(path) return path:match("^%.gen4Trades%[%d+%]%.language$") end },
  -- German build: the wallpaper-password alphabet is German easy-chat words
  { file = "constants.lua", path = ".passwordWords", why = "German password word list" },
  -- German build: its own title logo palette, and no US legal overlay in
  -- the opening (op_demo.narc members 113..115 do not exist)
  { file = "gen4_graphics.lua", path = ".palettes[title/logo]", why = "German title logo" },
  { file = "gen4_menus.lua", path = ".title.logo.content", why = "German title logo's drawn box" },
  { file = "gen4_graphics.lua", path = ".screens[opening/first_overlay]", why = "no US legal overlay in the German opening" },
  -- German build: the staff roll is laid out for German credits
  { file = "gen4_ending.lua", path = ".roll", why = "German staff roll spacing" },
  -- the trainer AI reader keeps a margin past Terminate (word 10607); the
  -- words after it are the overlay's next table, which holds RAM pointers
  { file = "gen4_trainer_ai.lua", why = "overlay words past the AI script",
    test = function(path)
      local i = tonumber(path:match("^%.words%[(%d+)%]$"))
      return i and i > 10607
    end },
}

-- Tables keyed by a NAME the cartridge spells in its own language: re-keyed
-- by something language-free before comparing.
local REKEY = {
  -- audio.cries is keyed by species name (Sound.playCry's Gen 1-3 shape);
  -- the cry file is "cries/NNN.wav" by species id
  ["audio.lua"] = function(t)
    if type(t) == "table" and type(t.cries) == "table" then
      local byFile = {}
      for _, def in pairs(t.cries) do
        if type(def) == "table" and def.file then byFile[def.file] = def end
      end
      t.cries = byFile
    end
    return t
  end,
}

local function listDir(dir)
  local out = {}
  local p = io.popen(('dir /b "%s"'):format((dir:gsub("/", "\\"))))
  if p then
    for line in p:lines() do out[#out + 1] = line end
    p:close()
  end
  table.sort(out)
  return out
end

local function load(path)
  local chunk = loadfile(path)
  if not chunk then return nil end
  local ok, v = pcall(chunk)
  return ok and v or nil
end

-- fold "…/001_bulbasaur.png" and "…/001.png" to the same thing
local function foldPath(s)
  return (s:gsub("/(%d%d%d)_[^/]*(%.%w+)$", "/%1%2"):gsub("/(%d%d%d)_[^/.]*$", "/%1"))
end

local function isTextKey(k)
  if type(k) ~= "string" then return false end
  if TEXT_KEYS[k] then return true end
  local lower = k:lower()
  return lower:find("name") or lower:find("text") or lower:find("label")
      or lower:find("desc") or lower:find("message") or lower:find("string")
end

local report = { text = {}, known = {}, address = {}, data = {} }
local function note(bin, file, path, a, b)
  local t = report[bin]
  t[file] = t[file] or { n = 0, first = {} }
  t[file].n = t[file].n + 1
  if #t[file].first < (verbose and 40 or 6) then
    local function show(v)
      if type(v) == "string" then
        local s = v:sub(1, 60):gsub("[%c\128-\255]", "?")
        return ("%q"):format(s)
      end
      return tostring(v)
    end
    t[file].first[#t[file].first + 1] = ("%s: %s ~= %s"):format(path, show(a), show(b))
  end
end

local function knownFor(file, path)
  for _, k in ipairs(KNOWN) do
    if k.file == file and (not k.path or path:sub(1, #k.path) == k.path)
       and (not k.test or k.test(path)) then return k end
  end
end

local function keyText(k)
  if type(k) == "string" and k:match("^[%a_][%w_]*$") then return "." .. k end
  return "[" .. tostring(k) .. "]"
end

local function walk(file, path, a, b, lastKey)
  if a == b then return end
  local ta, tb = type(a), type(b)
  if ta == "table" and tb == "table" then
    local seen = {}
    for k, v in pairs(a) do seen[k] = true; walk(file, path .. keyText(k), v, b[k], k) end
    for k, v in pairs(b) do if not seen[k] then walk(file, path .. keyText(k), nil, v, k) end end
    return
  end
  if ta == "string" and tb == "string" and foldPath(a) == foldPath(b) then return end
  if knownFor(file, path) then return note("known", file, path, a, b) end
  if ADDRESS_KEYS[lastKey] and ta == tb then return note("address", file, path, a, b) end
  if (ta == "string" or ta == "nil") and (tb == "string" or tb == "nil") and isTextKey(lastKey) then
    return note("text", file, path, a, b)
  end
  -- a string anywhere under a text key (names = { … }, text = { yes = … })
  if ta == "string" and tb == "string" then
    for segment in path:gmatch("%.([%a_][%w_]*)") do
      if TEXT_KEYS[segment] then return note("text", file, path, a, b) end
    end
  end
  note("data", file, path, a, b)
end

local usData, otherData = usDir .. "/data/generated", otherDir .. "/data/generated"
local files = listDir(usData)
assert(#files > 0, "no generated tables under " .. usData)
local missing = {}
for _, f in ipairs(files) do
  if f:match("%.lua$") and not TEXT_FILES[f] then
    local a, b = load(usData .. "/" .. f), load(otherData .. "/" .. f)
    if a == nil and b == nil then
      -- unloadable on both sides: not this check's business
    elseif b == nil then missing[#missing + 1] = f
    else
      if REKEY[f] then a, b = REKEY[f](a), REKEY[f](b) end
      walk(f, "", a, b, nil)
    end
  end
end

local function dump(bin, title)
  local names = {}
  for f in pairs(report[bin]) do names[#names + 1] = f end
  table.sort(names)
  local total = 0
  for _, f in ipairs(names) do total = total + report[bin][f].n end
  print(("%s: %d differences in %d tables"):format(title, total, #names))
  for _, f in ipairs(names) do
    print(("  %-36s %d"):format(f, report[bin][f].n))
    if bin ~= "text" or verbose then
      for _, line in ipairs(report[bin][f].first) do print("      " .. line) end
    end
  end
  return total
end

dump("text", "TEXT (expected: the cartridge's language)")
dump("known", "KNOWN (the cartridges differ here)")
dump("address", "ADDRESS (where a table was found; expected to move)")
local bad = dump("data", "DATA (must be zero)")
if #missing > 0 then print("MISSING on the other cartridge: " .. table.concat(missing, ", ")) end
assert(bad == 0 and #missing == 0, ("%d data differences, %d missing tables"):format(bad, #missing))
print("OK: no data differences outside text and the known cartridge differences")
