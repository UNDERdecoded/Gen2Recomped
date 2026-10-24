-- Which REVISION of which cartridge a file is, and what to tell the player
-- when it is one this build does not import.
--
-- GameVersion decides acceptance, by SHA-1, and that stays the only gate: an
-- extractor reads fixed addresses, symbol tables and code patterns that were
-- proven against one exact dump, so a hash match is the only promise that the
-- addresses mean what the extractor thinks they mean.  What this module adds is
-- the other half of the conversation.  A cartridge whose hash is NOT accepted
-- used to get one generic line ("needs a clean US dump; patched dumps never
-- verify"), which is wrong for the most common case: a perfectly clean dump of
-- a different retail revision.  A FireRed Rev 1 owner was told their cart was
-- patched.  Now the header is read (game code, region, mask-ROM revision) and
-- the message names exactly what was found and why it is not imported.
--
-- REVISIONS, per game, as of this file (docs/rom-revisions.md has the table
-- and the evidence for each line):
--
--   Red / Blue      one English release, (USA, Europe)         accepted
--   Yellow          one English release, (USA, Europe)         accepted
--   Gold / Silver   one English release, (USA, Europe)         accepted
--   Crystal         Rev 0 (USA), Rev 1 (USA, Europe)           both accepted
--                   (Australia) BYTU                           NOT YET
--   FireRed         Rev 0 (USA, Europe)                        accepted
--                   Rev 1, Switch Online build                 NOT YET
--   Emerald         one release, (USA, Europe)                 accepted
--   Platinum        Rev 0, Rev 1 (USA)                         both accepted
--                   (Europe) CPUP                              NOT YET
--   HeartGold       (USA) IPKE; SoulSilver (USA, Australia)    accepted
--                   (Europe) IPKP / IPGP                       NOT YET
--   Black / White   (USA, Europe) IRBO / IRAO                  accepted
--
-- The KNOWN hashes below come from pret's own per-build `.sha1` files
-- (pokefirered firered_rev1.sha1 / firered_switch.sha1 / leafgreen*.sha1,
-- pokecrystal roms.sha1), so a known-but-unsupported revision is named by its
-- hash, not guessed from a header that a patch could have rewritten.
--
-- Zero requires, like GameVersion, so the import worker thread can load it.

local RomRevisions = {}

-- ---------------------------------------------------------------------------
-- Every dump an import accepts, by SHA-1.  This mirrors GameVersion's
-- sha1/sha1Alt exactly (tests/rom_revisions_test.lua holds the two together);
-- it exists so a message can say "this build imports Rev 0 and Rev 1" without
-- inventing labels from hashes.
-- ---------------------------------------------------------------------------
RomRevisions.ACCEPTED = {
  red = {
    { sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a", code = "POKEMON RED", revision = 0, region = "USA, Europe",
      label = "Pokemon Red (USA, Europe)" },
  },
  blue = {
    { sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2", code = "POKEMON BLUE", revision = 0, region = "USA, Europe",
      label = "Pokemon Blue (USA, Europe)" },
  },
  yellow = {
    { sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1", code = "POKEMON YELLOW", revision = 0, region = "USA, Europe",
      label = "Pokemon Yellow (USA, Europe)" },
  },
  gold = {
    { sha1 = "d8b8a3600a465308c9953dfa04f0081c05bdcb94", code = "AAUE", revision = 0,
      label = "Pokemon Gold (USA, Europe)" },
  },
  silver = {
    { sha1 = "49b163f7e57702bc939d642a18f591de55d92dae", code = "AAXE", revision = 0,
      label = "Pokemon Silver (USA, Europe)" },
  },
  crystal = {
    { sha1 = "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133", code = "BYTE", revision = 0,
      label = "Pokemon Crystal (USA)" },
    { sha1 = "f2f52230b536214ef7c9924f483392993e226cfb", code = "BYTE", revision = 1,
      label = "Pokemon Crystal (USA, Europe) (Rev 1)" },
  },
  prism = {
    { sha1 = "752076692ae3387cf426ce5f51a98c6b60e8df6a", code = "PRSM", release = true,
      label = "Pokemon Prism (the release this build was mapped against)" },
  },
  polishedcrystal = {
    { sha1 = "6930b48af5844d373e3c9130f26d6dd1084cf4ed", code = "PKPC", release = true,
      label = "Polished Crystal 3.2.3" },
  },
  firered = {
    { sha1 = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", code = "BPRE", revision = 0,
      label = "Pokemon FireRed (USA, Europe)" },
  },
  leafgreen = {
    { sha1 = "574fa542ffebb14be69902d1d36f1ec0a4afd71e", code = "BPGE", revision = 0,
      label = "Pokemon LeafGreen (USA, Europe)" },
  },
  emerald = {
    { sha1 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7", code = "BPEE", revision = 0,
      label = "Pokemon Emerald (USA, Europe)" },
  },
  platinum = {
    { sha1 = "ce81046eda7d232513069519cb2085349896dec7", code = "CPUE", revision = 0,
      label = "Pokemon Platinum (USA)" },
    { sha1 = "0862ec35b24de5c7e2dcb88c9eea0873110d755c", code = "CPUE", revision = 1,
      label = "Pokemon Platinum (USA) (Rev 1)" },
  },
  heartgold = {
    { sha1 = "4fcded0e2713dc03929845de631d0932ea2b5a37", code = "IPKE", revision = 0,
      label = "Pokemon HeartGold (USA)" },
  },
  soulsilver = {
    { sha1 = "f8dc38ea20c17541a43b58c5e6d18c1732c7e582", code = "IPGE", revision = 0,
      label = "Pokemon SoulSilver (USA, Australia)" },
  },
  black = {
    { sha1 = "26ad0b9967aa279c4a266ee69f52b9b2332399a5", code = "IRBO", revision = 0,
      label = "Pokemon Black (USA, Europe)" },
  },
  white = {
    { sha1 = "bc696a0dfb448c7b3a8a206f0f8214411a039208", code = "IRAO", revision = 0,
      label = "Pokemon White (USA, Europe)" },
  },
}

-- ---------------------------------------------------------------------------
-- Retail builds that are KNOWN, by hash, and deliberately not accepted, with
-- the reason in one sentence the launcher can show as-is.
-- ---------------------------------------------------------------------------
RomRevisions.KNOWN = {
  -- pret/pokefirered firered_rev1.sha1
  ["dd5945db9b930750cb39d00c84da8571feebf417"] = {
    game = "firered", code = "BPRE", revision = 1,
    label = "Pokemon FireRed (USA, Europe) (Rev 1)",
    why = "Rev 1 shifts about 45,000 of FireRed's 49,229 ROM symbols by 20 to "
       .. "120 bytes (pret pokefirered_rev1.sym), and the FireRed extractor "
       .. "still reads hundreds of fixed Rev 0 addresses and code patterns",
  },
  -- pret/pokefirered firered_switch.sha1 (header revision 10)
  ["baa452d0b24629dd7782cfc07a8984085dde1311"] = {
    game = "firered", code = "BPRE", revision = 10,
    label = "Pokemon FireRed (Nintendo Switch Online build)",
    why = "the Switch Online build has its own memory layout (pret builds it "
       .. "with a separate linker script) and the extractor is mapped to Rev 0",
  },
  -- pret/pokefirered leafgreen*.sha1
  ["7862c67bdecbe21d1d69ce082ce34327e1c6ed5e"] = {
    game = "leafgreen", code = "BPGE", revision = 1,
    label = "Pokemon LeafGreen (USA, Europe) (Rev 1)",
  },
  ["62b9fc77549dbc67032eb6cbd0ea6ad3b825690f"] = {
    game = "leafgreen", code = "BPGE", revision = 10,
    label = "Pokemon LeafGreen (Nintendo Switch Online build)",
  },
  -- pret/pokecrystal roms.sha1, pokecrystal_au.gbc
  ["a0fc810f1d4e124434f7be2c989ab5b5892ddf36"] = {
    game = "crystal", code = "BYTU", revision = 0,
    label = "Pokemon Crystal (Australia)",
    why = "the Australian build rewrites the Celadon Game Corner and other "
       .. "scripts, which moves the script banks the Crystal symbol table "
       .. "describes, and no symbol table for it has been mapped",
  },
}

-- ---------------------------------------------------------------------------
-- Header identification.
-- ---------------------------------------------------------------------------

-- Display names for the games, by version id.  Games this port does not
-- import at all are here too so the message can name them.
local GAME_NAMES = {
  red = "Pokemon Red", blue = "Pokemon Blue", yellow = "Pokemon Yellow",
  green = "Pokemon Green",
  gold = "Pokemon Gold", silver = "Pokemon Silver", crystal = "Pokemon Crystal",
  prism = "Pokemon Prism", polishedcrystal = "Polished Crystal",
  ruby = "Pokemon Ruby", sapphire = "Pokemon Sapphire",
  firered = "Pokemon FireRed", leafgreen = "Pokemon LeafGreen",
  emerald = "Pokemon Emerald",
  diamond = "Pokemon Diamond", pearl = "Pokemon Pearl",
  platinum = "Pokemon Platinum",
  heartgold = "Pokemon HeartGold", soulsilver = "Pokemon SoulSilver",
  black = "Pokemon Black", white = "Pokemon White",
  black2 = "Pokemon Black 2", white2 = "Pokemon White 2",
}
RomRevisions.GAME_NAMES = GAME_NAMES

-- GBA and DS game codes, first three letters.
local CODE_GAMES = {
  AXV = "ruby", AXP = "sapphire", BPR = "firered", BPG = "leafgreen",
  BPE = "emerald",
  ADA = "diamond", APA = "pearl", CPU = "platinum",
  IPK = "heartgold", IPG = "soulsilver",
  IRB = "black", IRA = "white", IRE = "black2", IRD = "white2",
}

-- Gen 2 manufacturer codes (header 0x13F), first three letters.
local GB_CODE_GAMES = {
  AAU = "gold", AAX = "silver", BYT = "crystal", PRS = "prism", PKP = "polishedcrystal",
}

-- Gen 1 titles, every language a cartridge was released in.  English
-- releases share the title with the Japanese one, so the destination byte
-- (0x14A) is what separates them.
local GB_TITLES = {
  ["POKEMON RED"] = "red", ["POKEMON BLUE"] = "blue",
  ["POKEMON YELLOW"] = "yellow", ["POKEMON GREEN"] = "green",
  ["POKEMON ROUGE"] = "red", ["POKEMON BLEUE"] = "blue", ["POKEMON JAUNE"] = "yellow",
  ["POKEMON ROT"] = "red", ["POKEMON BLAU"] = "blue", ["POKEMON GELB"] = "yellow",
  ["POKEMON ROSSO"] = "red", ["POKEMON BLU"] = "blue", ["POKEMON GIALLO"] = "yellow",
  ["POKEMON ROJO"] = "red", ["POKEMON AZUL"] = "blue", ["POKEMON AMARILL"] = "yellow",
}

-- The fourth letter of a game code.  'O' is the international English build
-- Black and White shipped as (USA, Europe).
local REGIONS = {
  E = "USA", P = "Europe", U = "Australia", J = "Japan", K = "Korea",
  F = "France", D = "Germany", I = "Italy", S = "Spain", H = "Netherlands",
  O = "USA, Europe", X = "Europe", Y = "Europe", Z = "Europe",
}

local function byte(s, off) return s:byte(off + 1) or 0 end

local function cstr(s, from, len)
  local raw = s:sub(from + 1, from + len)
  raw = raw:gsub("%z.*$", "")
  return (raw:gsub("[^%w%p ]", ""):gsub("%s+$", ""))
end

-- Read a cartridge header.  Returns nil for anything that is not a GB, GBA or
-- DS header, else { platform, title, code, region, revision, game }.
function RomRevisions.header(bytes)
  if type(bytes) ~= "string" then return nil end
  -- Nintendo DS: the header CRC of the logo at 0x15C is always 0xCF56
  if #bytes >= 0x200 and byte(bytes, 0x15C) == 0x56 and byte(bytes, 0x15D) == 0xCF then
    local code = cstr(bytes, 0x0C, 4)
    return { platform = "nds", title = cstr(bytes, 0x00, 12), code = code,
             region = REGIONS[code:sub(4, 4)], revision = byte(bytes, 0x1E),
             game = CODE_GAMES[code:sub(1, 3)] }
  end
  -- Game Boy Advance: 0xB2 is the fixed value 0x96, the logo starts 24 FF AE 51
  if #bytes >= 0xC0 and byte(bytes, 0xB2) == 0x96 and byte(bytes, 0x04) == 0x24
     and byte(bytes, 0x05) == 0xFF then
    local code = cstr(bytes, 0xAC, 4)
    return { platform = "gba", title = cstr(bytes, 0xA0, 12), code = code,
             region = REGIONS[code:sub(4, 4)], revision = byte(bytes, 0xBC),
             game = CODE_GAMES[code:sub(1, 3)] }
  end
  -- Game Boy / Color: the logo starts CE ED 66 66 at 0x104
  if #bytes >= 0x150 and byte(bytes, 0x104) == 0xCE and byte(bytes, 0x105) == 0xED
     and byte(bytes, 0x106) == 0x66 and byte(bytes, 0x107) == 0x66 then
    local cgb = byte(bytes, 0x143)
    local revision = byte(bytes, 0x14C)
    local overseas = byte(bytes, 0x14A) == 1
    if cgb == 0x80 or cgb == 0xC0 then
      -- a Color title is 11 characters, then the four-letter manufacturer code
      local code = cstr(bytes, 0x13F, 4)
      local game = GB_CODE_GAMES[code:sub(1, 3)]
      if game then
        return { platform = "gbc", title = cstr(bytes, 0x134, 11), code = code,
                 region = REGIONS[code:sub(4, 4)], revision = revision, game = game }
      end
    end
    local title = cstr(bytes, 0x134, 16)
    local game = GB_TITLES[title]
    local region
    if game then
      -- English and Japanese carts share the title; the other languages
      -- were European releases with their own
      local shared = title == "POKEMON RED" or title == "POKEMON BLUE"
        or title == "POKEMON YELLOW" or title == "POKEMON GREEN"
      region = shared and (overseas and "USA, Europe" or "Japan") or "Europe"
    end
    return { platform = "gb", title = title, code = title, region = region,
             revision = revision, game = game }
  end
  return nil
end

local function revisionText(revision)
  if not revision or revision == 0 then return "" end
  return (" (Rev %d)"):format(revision)
end

local function headerLabel(h)
  local name = GAME_NAMES[h.game] or ("\"" .. (h.title or "?") .. "\"")
  local region = h.region and (" (" .. h.region .. ")") or ""
  return name .. region .. revisionText(h.revision)
end

local function acceptedList(game)
  local labels = {}
  for _, row in ipairs(RomRevisions.ACCEPTED[game] or {}) do
    labels[#labels + 1] = row.label
  end
  if #labels == 0 then return nil end
  if #labels == 1 then return labels[1] end
  return table.concat(labels, ", ", 1, #labels - 1) .. " and " .. labels[#labels]
end

-- The accepted row for a SHA-1, if any (game id, row).
function RomRevisions.acceptedRow(sha1)
  for game, rows in pairs(RomRevisions.ACCEPTED) do
    for _, row in ipairs(rows) do
      if row.sha1 == sha1 then return game, row end
    end
  end
  return nil
end

-- Explain a file that GameVersion did NOT accept.  `bytes` needs only the
-- first 0x200 bytes; `sha1` is the hex digest the importer already computed.
-- Returns nil when the file is not a recognisable Pokemon cartridge (the
-- caller keeps its generic message), else
--   { game, label, short, message, known = bool }
-- `short` fits in a list of rejected names; `message` is the full sentence.
function RomRevisions.describe(bytes, sha1)
  sha1 = sha1 and sha1:lower()
  local known = sha1 and RomRevisions.KNOWN[sha1]
  local h = RomRevisions.header(bytes)
  if known then
    local accepted = acceptedList(known.game)
    local msg
    if accepted then
      msg = ("This is %s. This build imports %s only; that revision is not "
        .. "supported yet because %s."):format(known.label, accepted,
        known.why or "it has not been mapped")
    else
      msg = ("This is %s, a clean retail dump, but %s is not one of the games "
        .. "this build imports."):format(known.label, GAME_NAMES[known.game] or known.game)
    end
    return { game = known.game, label = known.label, known = true,
             short = known.label .. " - not supported yet", message = msg }
  end
  if not h or not h.game then
    if h and h.title and h.title:upper():match("^POK") then
      return { label = h.title, known = false,
               short = "unrecognised Pokemon cartridge \"" .. h.title .. "\"",
               message = ("The header says \"%s\" (code %s, revision %d), which "
                 .. "is not a cartridge this build knows."):format(h.title,
                 tostring(h.code), h.revision or 0) }
    end
    return nil
  end
  local label = headerLabel(h)
  local accepted = acceptedList(h.game)
  if not accepted then
    return { game = h.game, label = label, known = false,
             short = label .. " - not a game this build imports",
             message = ("This looks like %s (%s, revision %d). That game is not "
               .. "one this build imports."):format(label, h.code, h.revision or 0) }
  end
  -- Same game: is it the code and revision we accept, with the wrong bytes?
  for _, row in ipairs(RomRevisions.ACCEPTED[h.game]) do
    if row.release and row.code == h.code then
      return { game = h.game, label = row.label, known = false,
               short = (GAME_NAMES[h.game] or h.game) .. " - a different release",
               message = ("This is a %s release other than the one this build "
                 .. "was mapped against (%s), or a modified copy of it. Romhack "
                 .. "addresses move between releases, so only that exact file "
                 .. "imports."):format(GAME_NAMES[h.game] or h.game, row.label) }
    end
    if row.code == h.code and row.revision == h.revision
       and (row.region == nil or row.region == h.region) then
      return { game = h.game, label = label, known = false,
               short = label .. " - modified or bad dump",
               message = ("The header says %s, which is supported, but the file "
                 .. "does not match the clean dump (%s). It may be patched, "
                 .. "incomplete, overdumped or \"fixed\" (tagged [b] or [BF]); use "
                 .. "an unmodified dump. Padding-only trimming is supported "
                 .. "for HeartGold, SoulSilver, Black and White when all game "
                 .. "data matches exactly."):format(label, row.label) }
    end
  end
  return { game = h.game, label = label, known = false,
           short = label .. " - revision not supported yet",
           message = ("This looks like %s (game code %s, revision %d). This build "
             .. "imports %s only; this revision or region has not been mapped "
             .. "yet."):format(label, h.code, h.revision or 0, accepted) }
end

return RomRevisions
