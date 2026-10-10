-- Gen3Save -- the Emerald battery codec.
--
-- A Gen 3 save is not a flat image the way Gen 1 and Gen 2 saves are.  It is
-- 128 KiB of flash holding TWO complete save slots that the game alternates
-- between, each slot fourteen 4 KiB sectors, each sector carrying a footer
-- that says which part of which structure it holds.  Nothing about that is
-- guessable from the bytes, so none of it is guessed here: the sector layout,
-- the checksum, the footer signature and the Pokemon substructure orders all
-- arrive from the manifest, where tools/gen3_discover.py derived them from the
-- cartridge -- the layout from the one table in 16 MiB with that shape, the
-- checksum by reading CalculateChecksum's instructions, and the substructure
-- orders by interpreting the 24-way switch that decides them, one case at a
-- time.  See that tool's "the save file" section.
--
-- WHY THE SLOTS MATTER.  A reader that takes slot A because it comes first is
-- right about half the time, and the other half it silently loads the previous
-- save -- which looks like the game losing progress rather than like a bug in
-- the reader.  The rule is the sector counter: whichever slot holds the higher
-- one is current, with wraparound at the point where one slot is at 0 and the
-- other is at the maximum.
--
-- WHY THE POKEMON ARE ENCRYPTED.  Each one's 48 "secure" bytes are XORed with
-- personality ^ otId and cut into four 12-byte substructures -- Growth,
-- Attacks, EVs, Misc -- whose ORDER rotates with personality % 24.  Decrypting
-- with the wrong key or reading the substructures in the wrong order both
-- produce plausible-looking nonsense, which is why every mon is checked
-- against its own stored checksum before anything is believed.
--
-- Pure Lua, no love.* at require time, same as GenSave and Gen2Save.

local ok_bit, bit = pcall(require, "bit")
if not ok_bit then bit = nil end

local Gen3Save = {}

Gen3Save.SAVE_SIZE = 128 * 1024
Gen3Save.SECTOR_SIZE = 4096
Gen3Save.SECTORS_PER_SLOT = 14
Gen3Save.TOTAL_SECTORS = 32          -- the last four are the hall of fame and
                                     -- friends; the two slots use 0..27
-- Offsets inside a sector's 16-byte footer.
Gen3Save.FOOTER = { id = 0x0FF4, checksum = 0x0FF6, security = 0x0FF8,
                    counter = 0x0FFC }
Gen3Save.SECURITY = 0x08012025

-- Filled by setLayout() from the manifest.  Deliberately nil until then: a
-- codec that invents a layout when it was not given one is a codec that
-- silently mis-reads a save.
Gen3Save.layout = nil
Gen3Save.substructOrders = nil

Gen3Save.SUBSTRUCTS = { "growth", "attacks", "evs", "misc" }

-- The plain part of a box record, which is forced by where the checksum sits
-- (28): personality 0, trainer id 4, nickname 8, language 18, flags 19,
-- trainer name 20, markings 27.  Nothing else tiles twenty-eight bytes.
Gen3Save.NICKNAME_LENGTH = 10
Gen3Save.OT_NAME_LENGTH = 7
-- The flags byte is a bitfield and only two of its bits mean anything to a
-- writer.  HAS_SPECIES is the one that decides whether the cartridge sees a
-- Pokemon at all: a record with it clear is an empty slot however complete
-- the rest of it is, which is what a party written into zeroed bytes would
-- have been.
Gen3Save.MON_BAD_EGG = 1
Gen3Save.MON_HAS_SPECIES = 2
Gen3Save.MON_IS_EGG = 4
-- THE TWO NUMBERS IN THIS FILE THAT ARE NOT DERIVED, and the shape of where
-- they are used is what makes them safe.
--
-- A Pokemon record names the language its two names are written in and the
-- GAME it was met in.  Neither is a layout fact -- they are the cartridge's
-- own `gGameLanguage` and `gGameVersion`, two constants compiled into it --
-- and neither can be read out of a save layout.
--
-- They are used in exactly one situation: a Pokemon born in THIS PORT, in a
-- save that was never imported, so there is no byte to carry over and no
-- other record to copy one from.  Every Pokemon that came off a cartridge
-- keeps the bytes it arrived with, and a save that holds even one such record
-- hands its own answer to every mon written beside it (Gen3Save.saveDefaults).
-- So these are the fallback for a playthrough with nothing in it to ask, and
-- the moment there is something to ask, they are not used at all.
Gen3Save.LANGUAGE_ENGLISH = 2
Gen3Save.MET_GAME_EMERALD = 3
Gen3Save.MET_GAME_FIRE_RED = 4
Gen3Save.MET_GAME_LEAF_GREEN = 5
Gen3Save.defaultMetGame = Gen3Save.MET_GAME_EMERALD

-- What language and game of origin THIS save already says, taken from the
-- first complete record in it.  A save carrying real cartridge Pokemon
-- answers out of its own bytes; one carrying none falls back to the two
-- constants above.
function Gen3Save.saveDefaults(blocks)
  local out = { language = Gen3Save.LANGUAGE_ENGLISH,
                metGame = Gen3Save.defaultMetGame or Gen3Save.MET_GAME_EMERALD }
  local f = Gen3Save.fields
  if not (f and blocks) then return out end
  local function ask(source, at)
    if out.found or not source then return end
    local ok, mon = pcall(Gen3Save.decodeBoxMon, source, at)
    if ok and mon and not mon.empty and mon.checksumOk
       and mon.language and mon.language ~= 0 then
      out.language = mon.language
      local origins = Gen3Save.unpackOrigins(mon.origins)
      if origins.metGame and origins.metGame > 0 then
        out.metGame = origins.metGame
      end
      out.found = true
    end
  end
  if f.party and blocks.block1 then
    for i = 1, f.party.size do
      ask(blocks.block1, f.party.start + (i - 1) * f.party.monSize)
    end
  end
  local st = f.storage
  if st and blocks.storage then
    for b = 0, st.boxCount - 1 do
      for slot = 0, st.boxCapacity - 1 do
        ask(blocks.storage,
            st.boxes + (b * st.boxCapacity + slot) * st.boxMonSize)
      end
    end
  end
  return out
end

-- Where the fields sit inside the save blocks.  Also from the manifest, also
-- derived rather than remembered: the two save-block pointers were told apart
-- by which block's size their accesses fit inside, and each field came out of
-- the code that reads it -- the flags out of the function setflag, clearflag
-- and checkflag all reach, the variables out of the one that also loads
-- gSpecialVars, money out of the handler that builds 0x490 as `0x92 << 3` and
-- never puts it in a literal pool at all.
Gen3Save.fields = nil

function Gen3Save.setLayout(layout, orders, fields, gameVersion)
  Gen3Save.layout = layout
  Gen3Save.substructOrders = orders
  Gen3Save.fields = fields
  if gameVersion == "firered" then
    Gen3Save.defaultMetGame = Gen3Save.MET_GAME_FIRE_RED
  elseif gameVersion == "leafgreen" then
    Gen3Save.defaultMetGame = Gen3Save.MET_GAME_LEAF_GREEN
  else
    Gen3Save.defaultMetGame = Gen3Save.MET_GAME_EMERALD
  end
end

-- ---------------------------------------------------------------------------
-- little-endian readers.  A save is bytes, not a string of characters, and
-- every width here is the width the cartridge writes.
-- ---------------------------------------------------------------------------
local function u8(b, o) return b:byte(o + 1) or 0 end
local function u16(b, o) return u8(b, o) + u8(b, o + 1) * 256 end
local function u32(b, o)
  return u8(b, o) + u8(b, o + 1) * 256 + u8(b, o + 2) * 65536
         + u8(b, o + 3) * 16777216
end

local function xorU32(a, b)
  if bit then return bit.band(bit.bxor(a, b), 0xFFFFFFFF) end
  local out, mul = 0, 1
  for _ = 1, 4 do
    local x, y = a % 256, b % 256
    local byte = 0
    for k = 0, 7 do
      local p = 2 ^ k
      local xb = math.floor(x / p) % 2
      local yb = math.floor(y / p) % 2
      if xb ~= yb then byte = byte + p end
    end
    out = out + byte * mul
    a, b, mul = math.floor(a / 256), math.floor(b / 256), mul * 256
  end
  return out
end
Gen3Save.xorU32 = xorU32

-- ---------------------------------------------------------------------------
-- The checksum, exactly as CalculateChecksum computes it: sum size/4 words,
-- then fold the top half onto the bottom.  Read out of the ROM rather than
-- remembered -- `lsl #16; lsr #18` is the division by four, and
-- `lsr #16; add; lsl #16; lsr #16` is the fold.
-- ---------------------------------------------------------------------------
function Gen3Save.checksum(bytes, from, size)
  local sum = 0
  for i = 0, math.floor(size / 4) - 1 do
    sum = (sum + u32(bytes, from + i * 4)) % 4294967296
  end
  return (math.floor(sum / 65536) + sum) % 65536
end

-- ---------------------------------------------------------------------------
-- sectors
-- ---------------------------------------------------------------------------
function Gen3Save.sector(bytes, index)
  local base = index * Gen3Save.SECTOR_SIZE
  return {
    index = index,
    base = base,
    id = u16(bytes, base + Gen3Save.FOOTER.id),
    storedChecksum = u16(bytes, base + Gen3Save.FOOTER.checksum),
    security = u32(bytes, base + Gen3Save.FOOTER.security),
    counter = u32(bytes, base + Gen3Save.FOOTER.counter),
  }
end

-- A slot is valid only if every one of its fourteen sectors signs itself, the
-- fourteen ids are 0..13 with none missing, and each sector's own checksum
-- agrees.  Any one of those failing means the slot was half-written, which is
-- precisely the case the two-slot design exists to survive.
function Gen3Save.readSlot(bytes, slot)
  local layout = Gen3Save.layout
  if not layout then error("Gen3Save: no sector layout (setLayout first)") end
  local first = slot * Gen3Save.SECTORS_PER_SLOT
  local seen, counter, bad = {}, nil, {}
  local sectors = {}
  for k = 0, Gen3Save.SECTORS_PER_SLOT - 1 do
    local s = Gen3Save.sector(bytes, first + k)
    if s.security ~= Gen3Save.SECURITY then
      bad[#bad + 1] = ("sector %d is not signed"):format(first + k)
    elseif s.id >= Gen3Save.SECTORS_PER_SLOT then
      bad[#bad + 1] = ("sector %d claims id %d"):format(first + k, s.id)
    else
      local size = layout.sectors[s.id + 1].size
      local got = Gen3Save.checksum(bytes, s.base, size)
      if got ~= s.storedChecksum then
        bad[#bad + 1] = ("sector %d (id %d) checksum %04X, stored %04X")
                        :format(first + k, s.id, got, s.storedChecksum)
      end
      seen[s.id] = s
      counter = s.counter
    end
    sectors[k + 1] = s
  end
  for id = 0, Gen3Save.SECTORS_PER_SLOT - 1 do
    if not seen[id] then bad[#bad + 1] = ("no sector holds id %d"):format(id) end
  end
  return { slot = slot, sectors = sectors, byId = seen, counter = counter,
           valid = #bad == 0, problems = bad }
end

-- Which slot the game would load.  The counter increments every save and wraps,
-- so "higher wins" needs the wrap case spelled out: a slot at 0 beats one at
-- 0xFFFFFFFF.  Only valid slots are candidates -- a half-written slot is
-- exactly what the other one is for.
function Gen3Save.currentSlot(bytes)
  local a, b = Gen3Save.readSlot(bytes, 0), Gen3Save.readSlot(bytes, 1)
  if not a.valid and not b.valid then return nil, a, b end
  local MAX = 4294967295
  local counter
  if not b.valid then
    counter = a.counter
  elseif not a.valid then
    counter = b.counter
  elseif a.counter == 0 and b.counter == MAX then
    counter = a.counter
  elseif b.counter == 0 and a.counter == MAX then
    counter = b.counter
  elseif a.counter >= b.counter then
    counter = a.counter
  else
    counter = b.counter
  end

  local current = (counter % 2 == 0) and a or b
  if not current.valid or current.counter ~= counter then
    local state = current.valid
      and ("carries counter " .. tostring(current.counter))
      or "is not intact"
    return nil, a, b,
      ("save counter %d points to physical slot %d, but that slot %s")
      :format(counter, counter % 2, state)
  end
  return current, a, b
end

-- Reassemble the three save structures out of the current slot's sectors.
-- Each sector carries a chunk of one structure at a known offset, and the
-- fourteen chunks tile the three structures exactly -- which the manifest
-- checked when it derived them.
function Gen3Save.readBlocks(bytes)
  local layout = Gen3Save.layout
  if not layout then error("Gen3Save: no sector layout (setLayout first)") end
  local current, a, b, why = Gen3Save.currentSlot(bytes)
  if not current then
    return nil, why or "neither save slot is intact", a, b
  end
  local parts = { block2 = {}, block1 = {}, storage = {} }
  for id = 0, Gen3Save.SECTORS_PER_SLOT - 1 do
    local s = current.byId[id]
    local row = layout.sectors[id + 1]
    local chunk = bytes:sub(s.base + 1, s.base + row.size)
    local which = (id == 0) and "block2" or (id <= 4 and "block1" or "storage")
    parts[which][#parts[which] + 1] = { offset = row.offset, data = chunk }
  end
  local function join(list, total)
    local buf = {}
    table.sort(list, function(x, y) return x.offset < y.offset end)
    local at = 0
    for _, piece in ipairs(list) do
      if piece.offset ~= at then
        error(("Gen3Save: chunk gap at %d (expected %d)"):format(piece.offset, at))
      end
      buf[#buf + 1] = piece.data
      at = at + #piece.data
    end
    if total and at ~= total then
      error(("Gen3Save: structure is %d bytes, layout says %d"):format(at, total))
    end
    return table.concat(buf)
  end
  return {
    slot = current.slot,
    counter = current.counter,
    block2 = join(parts.block2, layout.saveBlock2Size),
    block1 = join(parts.block1, layout.saveBlock1Size),
    storage = join(parts.storage, layout.pokemonStorageSize),
  }
end

-- ---------------------------------------------------------------------------
-- Pokemon
--
-- 80 bytes in a box, 100 in a party.  The first 32 are plain; the last 48 are
-- XORed with personality ^ otId and cut into four 12-byte substructures whose
-- order rotates with personality % 24.  The stored checksum is over the
-- DECRYPTED 48 bytes as 24 halfwords, which makes it an honest test of both
-- the key and the read: a mon that decrypts wrong will not match it.
-- ---------------------------------------------------------------------------
Gen3Save.BOX_MON_SIZE = 80
Gen3Save.PARTY_MON_SIZE = 100
Gen3Save.SECURE_OFFSET = 32
Gen3Save.SECURE_SIZE = 48
Gen3Save.SUBSTRUCT_SIZE = 12

function Gen3Save.decodeBoxMon(bytes, off)
  local orders = Gen3Save.substructOrders
  if not orders then error("Gen3Save: no substructure orders (setLayout first)") end
  local personality = u32(bytes, off)
  local otId = u32(bytes, off + 4)
  local key = xorU32(personality, otId)
  local secure = {}
  for i = 0, Gen3Save.SECURE_SIZE / 4 - 1 do
    local word = xorU32(u32(bytes, off + Gen3Save.SECURE_OFFSET + i * 4), key)
    secure[i * 4 + 1] = word % 256
    secure[i * 4 + 2] = math.floor(word / 256) % 256
    secure[i * 4 + 3] = math.floor(word / 65536) % 256
    secure[i * 4 + 4] = math.floor(word / 16777216) % 256
  end
  local sum = 0
  for i = 0, Gen3Save.SECURE_SIZE / 2 - 1 do
    sum = (sum + secure[i * 2 + 1] + secure[i * 2 + 2] * 256) % 65536
  end
  local stored = u16(bytes, off + 28)

  -- the order the four substructures sit in, straight off the cartridge
  local order = orders[(personality % 24) + 1]
  local subs = {}
  for k = 1, 4 do
    local slot = order[k]
    local base = slot * Gen3Save.SUBSTRUCT_SIZE
    local raw = {}
    for i = 1, Gen3Save.SUBSTRUCT_SIZE do raw[i] = secure[base + i] end
    subs[Gen3Save.SUBSTRUCTS[k]] = raw
  end

  local function h(raw, i) return raw[i + 1] + raw[i + 2] * 256 end
  local function w(raw, i)
    return raw[i + 1] + raw[i + 2] * 256 + raw[i + 3] * 65536
           + raw[i + 4] * 16777216
  end
  local g, a, e, m = subs.growth, subs.attacks, subs.evs, subs.misc
  return {
    personality = personality,
    otId = otId,
    checksum = stored,
    checksumOk = (sum == stored),
    empty = (personality == 0 and otId == 0),
    substructOrder = order,
    species = h(g, 0),
    heldItem = h(g, 2),
    experience = w(g, 4),
    ppBonuses = g[9],
    friendship = g[10],
    moves = { h(a, 0), h(a, 2), h(a, 4), h(a, 6) },
    pp = { a[9], a[10], a[11], a[12] },
    evs = { hp = e[1], attack = e[2], defense = e[3], speed = e[4],
            spAttack = e[5], spDefense = e[6] },
    contest = { cool = e[7], beauty = e[8], cute = e[9], smart = e[10],
                tough = e[11], sheen = e[12] },
    ivWord = w(m, 4),
    -- MISC IS FOUR FIELDS AND THIS READ ONE OF THEM, OFF BY A BYTE.
    --
    -- The substruct is pokerus(0), metLocation(1), a packed half-word at
    -- (2..3) and the IV word at (4..7).  `metLocation = m[3]` is Lua's
    -- one-based third byte, which is OFFSET TWO -- the low half of the
    -- packed word -- so every met location read out of a real cartridge save
    -- was a met LEVEL with four bits of the game of origin on top of it.
    --
    -- THE LAYOUT CANNOT BE ANYTHING ELSE, and that is the argument rather
    -- than pret's header: the IV word is read at offset 4 and has to be, or
    -- the six five-bit IVs and the egg and ability bits do not close on
    -- thirty-two.  That leaves four bytes in front of it for a byte, a byte
    -- and a half-word, and a half-word cannot start at offset three without
    -- running into the IVs.  So metLocation is offset ONE and the packed
    -- field is offset TWO, whatever it is called.
    --
    -- The suite could not catch it: gen3_save_test built its fixture by
    -- writing the met location at offset two, which is exactly where this
    -- was reading it.  A fixture that agrees with the decoder proves the two
    -- agree and nothing else, so the fixture is laid out the cartridge's way
    -- now and the fields below are what it checks.
    pokerus = m[1],
    metLocation = m[2],
    origins = h(m, 2),
    -- ---- AND THE PLAIN HEADER, which nothing read ------------------------
    --
    -- The first thirty-two bytes are not encrypted and four of their fields
    -- were going straight past: the NICKNAME, the LANGUAGE the nickname is
    -- written in, the ORIGINAL TRAINER'S NAME and the markings.  It cost
    -- nothing while an export could only be written onto the record's own
    -- bytes -- they were already there -- and it costs everything the moment
    -- a save is written from nothing, because then they are all that stands
    -- between a party and six blank-named Pokemon belonging to nobody.
    --
    -- The layout is forced by the checksum's position, which is known: four
    -- bytes of personality, four of trainer id, then ten of nickname (the
    -- longest name this cartridge will take), a language byte, a flags byte,
    -- seven of trainer name, one marking byte -- twenty-eight -- and the
    -- checksum at 28.  Nothing else tiles it.
    nicknameBytes = (function()
      local out = {}
      for i = 0, Gen3Save.NICKNAME_LENGTH - 1 do
        local b = u8(bytes, off + 8 + i)
        if b == 0xFF then break end
        out[#out + 1] = b
      end
      return out
    end)(),
    language = u8(bytes, off + 18),
    flags = u8(bytes, off + 19),
    otNameBytes = (function()
      local out = {}
      for i = 0, Gen3Save.OT_NAME_LENGTH - 1 do
        local b = u8(bytes, off + 20 + i)
        if b == 0xFF then break end
        out[#out + 1] = b
      end
      return out
    end)(),
    markings = u8(bytes, off + 27),
    substructs = subs,
  }
end

-- ...AND WHAT THAT HALF-WORD HOLDS.  Seven bits of met level, four of which
-- game it came from, FOUR OF WHICH BALL IT WAS CAUGHT IN, and one of the
-- original trainer's gender.
--
-- The ball is the reason this is read at all: Emerald sends a Pokemon out in
-- the ball it was caught in, so a save that drops those four bits sends
-- everything out in a POKe BALL -- which is what this port did, for every
-- Pokemon, whatever it was caught with.
function Gen3Save.unpackOrigins(word)
  word = math.floor(tonumber(word) or 0)
  return {
    metLevel = word % 128,
    metGame = math.floor(word / 128) % 16,
    ball = math.floor(word / 2048) % 16,
    otFemale = math.floor(word / 32768) % 2 == 1,
  }
end

-- The IVs, egg flag and ability bit are a packed 32-bit field in Misc: six
-- 5-bit IVs low to high, then isEgg, then which of the species' two abilities.
function Gen3Save.unpackIVs(word)
  local function nth(n) return math.floor(word / (2 ^ (n * 5))) % 32 end
  return {
    hp = nth(0), attack = nth(1), defense = nth(2),
    speed = nth(3), spAttack = nth(4), spDefense = nth(5),
    isEgg = math.floor(word / 2 ^ 30) % 2 == 1,
    altAbility = math.floor(word / 2 ^ 31) % 2 == 1,
  }
end

-- ...and both of them the other way, which a save written from NOTHING needs:
-- there is no record to patch, so every packed field has to be built.  Each
-- is the exact inverse of the reader above it, so the pair is checkable
-- against itself -- pack what unpack gave back and the word returns.
function Gen3Save.packIVs(ivs)
  ivs = ivs or {}
  local ORDER = { "hp", "attack", "defense", "speed", "spAttack", "spDefense" }
  local word = 0
  for i, k in ipairs(ORDER) do
    local v = math.floor(tonumber(ivs[k]) or 0)
    word = word + (math.max(0, math.min(31, v)) * 2 ^ ((i - 1) * 5))
  end
  if ivs.isEgg then word = word + 2 ^ 30 end
  if ivs.altAbility then word = word + 2 ^ 31 end
  return word
end

function Gen3Save.packOrigins(o)
  o = o or {}
  local word = math.max(0, math.min(127, math.floor(tonumber(o.metLevel) or 0)))
  word = word + math.max(0, math.min(15, math.floor(tonumber(o.metGame) or 0))) * 128
  word = word + math.max(0, math.min(15, math.floor(tonumber(o.ball) or 0))) * 2048
  if o.otFemale then word = word + 32768 end
  return word
end

-- Shininess is not stored; it is derived, which is why a save editor that
-- writes "shiny" as a flag never works.
function Gen3Save.isShiny(personality, otId)
  local function hi(v) return math.floor(v / 65536) % 65536 end
  local function lo(v) return v % 65536 end
  local x = xorU32(xorU32(lo(otId), hi(otId)), xorU32(lo(personality), hi(personality)))
  return x < 8
end

-- ---------------------------------------------------------------------------
-- reading the player out of the blocks
--
-- Money and coins are stored XORed with a word in SaveBlock2, which is the
-- one part of this that punishes a reader for guessing: read money without
-- the key and it comes back as a plausible-looking eight-digit number rather
-- than as anything obviously wrong.
-- ---------------------------------------------------------------------------
local function need(what)
  if not Gen3Save.fields then
    error("Gen3Save: no field offsets (setLayout first) -- cannot read " .. what)
  end
  return Gen3Save.fields
end

function Gen3Save.encryptionKey(block2)
  local f = need("the encryption key")
  return u32(block2, f.saveBlock2.encryptionKey)
end

-- The name is the cartridge's own text encoding, so it comes back as raw
-- bytes: decoding it is the charmap's job, not this codec's, and doing it
-- here would bake one game's charmap into every game's save reader.
function Gen3Save.playerNameBytes(block2)
  local f = need("the player name")
  local at = f.saveBlock2.playerName
  local out = {}
  for i = 0, 7 do
    local b = u8(block2, at + i)
    if b == 0xFF then break end
    out[#out + 1] = b
  end
  return out
end

function Gen3Save.readPlayer(blocks)
  local f = need("the player")
  local b1, b2 = blocks.block1, blocks.block2
  local key = Gen3Save.encryptionKey(b2)
  local s2 = f.saveBlock2
  return {
    nameBytes = Gen3Save.playerNameBytes(b2),
    gender = u8(b2, s2.playerGender),
    trainerId = u32(b2, s2.playerTrainerId),
    publicId = u16(b2, s2.playerTrainerId),
    secretId = u16(b2, s2.playerTrainerId + 2),
    playTime = {
      hours = u16(b2, s2.playTimeHours),
      minutes = u8(b2, s2.playTimeMinutes),
      seconds = u8(b2, s2.playTimeSeconds),
      vblanks = u8(b2, s2.playTimeVBlanks),
    },
    money = xorU32(u32(b1, f.saveBlock1.money), key),
    coins = xorU32(u16(b1, f.saveBlock1.coins), key) % 65536,
    -- BERRY POWDER lives in the OTHER block and under the same key.  The
    -- offset is derived by the import rather than carried in the manifest, so
    -- an older cache simply has not got it -- and a save read without it
    -- would come back with powder nobody can spend rather than none.
    berryPowder = f.saveBlock2.berryPowder
                  and xorU32(u32(b2, f.saveBlock2.berryPowder), key) or nil,
    -- BATTLE POINTS, which are NOT encrypted -- the three specials that add,
    -- take and read them all do a bare `ldrh`, and a currency this port
    -- XOR-ed on the way in would come back as tens of thousands of points.
    battlePoints = f.saveBlock2.battlePoints
                   and u16(b2, f.saveBlock2.battlePoints) or nil,
    -- DEWFORD's trend: two easy-chat words, NOT encrypted, and the hall's
    -- painting is named after their sum.
    dewfordTrend = f.saveBlock1.dewfordTrend
                   and { u16(b1, f.saveBlock1.dewfordTrend),
                         u16(b1, f.saveBlock1.dewfordTrend + 2) } or nil,
    -- THE GAME STATISTICS, under the same key as the money.  Sixty-four
    -- counters of how many times the player has done a thing, and the reason
    -- they are read at all is Mauville's STORYTELLER: every tale he tells is
    -- one of these read back, so a save imported without them meets a man
    -- with nothing to say about a player who has done everything.
    gameStats = Gen3Save.readGameStats(b1, key),
  }
end

-- The counters, keyed by their own index so a gap reads as nil rather than as
-- zero.  Their NUMBER is derived by the import (the run between the variables
-- and the berry trees); an older cache has no count and keeps none of them.
function Gen3Save.readGameStats(b1, key)
  local f = need("the game statistics")
  local at = tonumber(f.saveBlock1.gameStats)
  local count = tonumber(f.saveBlock1.gameStatCount)
  if not (at and count and count > 0) then return nil end
  -- keyed by the counter's own index, and a counter of zero is left out so
  -- the table reads the same way the engine's own does
  local out = {}
  for i = 0, count - 1 do
    local value = xorU32(u32(b1, at + i * 4), key)
    if value ~= 0 then out[i] = value end
  end
  return out
end

-- Flags are a bit array; variables are halfwords indexed from an id base that
-- is not zero.  Both bases were derived, and the two arrays abut exactly --
-- 300 flag bytes then 256 variables, with the game stats starting where they
-- end.  That agreement is what makes them trustworthy.
function Gen3Save.flag(block1, id)
  local f = need("a flag")
  if id == 0 then return false end
  local byte = f.saveBlock1.flags + math.floor(id / 8)
  if byte >= f.saveBlock1.vars then return nil end       -- past the array
  return math.floor(u8(block1, byte) / 2 ^ (id % 8)) % 2 == 1
end

-- ---------------------------------------------------------------------------
-- THE BERRY TREES, and every field in the record was read out of the code
-- that uses it rather than typed from a struct definition.
--
-- Eight bytes each, a hundred and twenty-eight of them, at the offset the
-- import derives (see RomExtractorGen3:berryTreeSaveBlock).  What is in those
-- eight bytes comes from four routines:
--
--   +0        berry            PlantBerryTree 0x00E191C stores it first
--   +1 bit7   stopGrowth       BerryTreeTimeUpdate 0x00E1894 skips the tree
--                              when it is set; AllowBerryTreeGrowth
--                              0x00E1A78 is four instructions that clear it
--   +1 bit0-6 stage            PlantBerryTree masks the stage with $7F
--   +2..3     minutes to go    strh at 0x00E194A, quadrupled for a fruiting
--                              tree at 0x00E196C
--   +4        yield            strb at 0x00E1966
--   +5 bit0-3 regrowth count   BerryTreeGrow 0x00E184E increments it and
--                              masks with $0F, blanking the tree at ten
--   +5 bit4-7 watered 1-4      GetNumStagesWatered 0x00E1A90 tests $10, $20,
--                              $40 and $80 of this byte and counts them
--   +6..7     padding
--
-- WHY THIS MATTERS AT ALL: Hoenn opens with eighty trees already fruiting, so
-- a save that carried no berry block came in with the region uprooted -- and
-- went back out the same way, taking the player's own plantings with it.
local BERRY_WATER_BITS = { 0x10, 0x20, 0x40, 0x80 }

function Gen3Save.berryTrees(block1)
  local f = Gen3Save.fields
  local block = f and f.berryTrees
  if not (block and block.offset) then return nil end
  local out = {}
  for i = 0, block.count - 1 do
    local at = block.offset + i * block.stride
    local berry = u8(block1, at)
    local packed = u8(block1, at + 1)
    local stage = packed % 128
    if berry > 0 and stage > 0 then
      local flags = u8(block1, at + 5)
      local watered = {}
      for w, bit in ipairs(BERRY_WATER_BITS) do
        watered[w] = (math.floor(flags / bit) % 2 == 1) or nil
      end
      out[i] = {
        berry = berry,
        stage = stage,
        minutes = u16(block1, at + 2),
        yield = u8(block1, at + 4),
        regrowth = flags % 16,
        watered = watered,
        stopGrowth = (packed >= 128) or nil,
      }
    end
  end
  return out
end

function Gen3Save.var(block1, id)
  local f = need("a variable")
  local index = id - (Gen3Save.fields.varsStartId or 0x4000)
  if index < 0 or index >= (f.varCount or 0) then return nil end
  return u16(block1, f.saveBlock1.vars + index * 2)
end

-- ---------------------------------------------------------------------------
-- the containers: party, bag, boxes
--
-- None of these could be found the way the scalar fields were.  Nothing reads
-- them at a fixed offset -- the bag hands each pocket's ADDRESS to a table in
-- RAM, the party is copied wholesale to and from a working array, and box
-- slots are indexed arithmetically -- so they were found by what the code does
-- with the addresses instead.  What makes them trustworthy is that laid end to
-- end they are contiguous: six hundred bytes of party, then money, coins, a
-- registered item, fifty PC slots and five bag pockets, each derived a
-- different way and each ending exactly where the next begins.
-- ---------------------------------------------------------------------------

function Gen3Save.party(block1)
  local f = need("the party")
  local p = f.party
  if not p then return nil end
  local count = math.min(u8(block1, p.count), p.size)
  local out = { count = count }
  for i = 1, count do
    local at = p.start + (i - 1) * p.monSize
    local mon = Gen3Save.decodeBoxMon(block1, at)
    -- A party Pokemon carries its computed stats after the 80 boxed bytes:
    -- status, level, current and maximum HP and the five battle stats.  Those
    -- are DERIVED values the game recomputes, so they are carried along rather
    -- than trusted.
    mon.slot = i
    mon.status = u32(block1, at + 80)
    mon.level = u8(block1, at + 84)
    mon.hp = u16(block1, at + 86)
    mon.maxHp = u16(block1, at + 88)
    out[i] = mon
  end
  return out
end

-- Every pocket is a run of four-byte slots: a two-byte item id and a two-byte
-- quantity.
--
-- ALL FIVE POCKETS HIDE THE QUANTITY, AND THE PC DOES NOT, and the cartridge
-- draws that line itself rather than it being remembered here.
-- ApplyNewEncryptionKeyToBagItems (ROM:00D658C) walks gBagPockets -- eight
-- bytes a pocket, the capacity at +4, the slot array behind the pointer at
-- +0 -- and for every slot passes `slots + item * 4 + 2` (the quantity) to
-- ApplyNewEncryptionKeyToHword (ROM:0077100).  Its outer loop ends
-- `cmp r1,#4 / bls`, which is pocket indices 0 THROUGH 4: all five.
--
-- Sitting in the twelve bytes immediately before that function are a pair of
-- one-instruction accessors -- `ldrh r0,[r0]; bx lr` at 00D6584 and
-- `strh r1,[r0]; bx lr` at 00D6588 -- with no XOR in them at all, beside the
-- pair at 00D6550 / 00D656C that do XOR through SaveBlock2+$AC.  Two kinds of
-- quantity, two kinds of accessor, next to each other: the encrypted one is
-- the bag's and the plain one is the PC's.
--
-- `key` is optional so a caller that only wants the item IDS (the layout
-- checks) need not have read SaveBlock2; without it `count` is the stored
-- halfword, which is what this function always returned and is a bag full of
-- tens of thousands of potions.
function Gen3Save.bag(block1, key)
  local f = need("the bag")
  local bag = f.bag
  if not bag then return nil end
  local out = {}
  for p, at in ipairs(bag.pockets) do
    local pocket = {}
    for slot = 0, bag.capacities[p] - 1 do
      local o = at + slot * bag.itemSlotSize
      local id, raw = u16(block1, o), u16(block1, o + 2)
      if id ~= 0 then
        local count = key and (xorU32(raw, key) % 65536) or raw
        pocket[#pocket + 1] = { item = id, count = count, raw = raw,
                                offset = o }
      end
    end
    out[p] = pocket
  end
  if bag.pcItems then
    local pc = {}
    for slot = 0, (bag.pcItemCount or 0) - 1 do
      local o = bag.pcItems + slot * bag.itemSlotSize
      local id = u16(block1, o)
      if id ~= 0 then pc[#pc + 1] = { item = id, count = u16(block1, o + 2) } end
    end
    out.pc = pc
  end
  return out
end

-- WHICH SAVEBLOCK1 ARRAY EACH POCKET IS.
--
-- Two different orders meet here and only one of them is in the manifest.
-- gItems[].pocket is the POCKET_* enum -- 1 items, 2 balls, 3 TMs and HMs,
-- 4 berries, 5 key items -- and the five arrays inside SaveBlock1 are laid
-- out in a different order again: items, key items, balls, TMs and HMs,
-- berries.  Only the offsets and capacities are derived, and an offset does
-- not say which pocket it holds.
--
-- SO THE ORDER IS CHECKED, not assumed, by the same argument the importer
-- uses on it: three of the five pockets hold EVERY item of their kind that
-- the game has -- sixteen slots for twelve balls, sixty-four for fifty-eight
-- TMs and HMs, forty-six for forty-three berries -- and no other assignment
-- of the five arrays satisfies all three at once.  The other two both hold
-- thirty and cannot be told apart by size, which is exactly why the three
-- that can are what the check rests on.
--
-- A bag that fails it is not written.  Scrambling a real cartridge's items
-- across the wrong arrays is worse than leaving them as they were.
Gen3Save.POCKET_ORDER = { "ITEM", "KEY_ITEM", "BALL", "TM_HM", "BERRY" }
Gen3Save.POCKET_HOLDS_ALL = { BALL = true, TM_HM = true, BERRY = true }

function Gen3Save.pocketOrder(cw)
  local bag = Gen3Save.fields and Gen3Save.fields.bag
  if not (bag and bag.capacities and bag.pockets) then
    return nil, "this cartridge's save layout has no bag in it"
  end
  local held = {}
  for _, def in pairs((cw and cw.itemDefs) or {}) do
    if type(def) == "table" and def.pocket then
      held[def.pocket] = (held[def.pocket] or 0) + 1
    end
  end
  for i, name in ipairs(Gen3Save.POCKET_ORDER) do
    local cap = bag.capacities[i]
    if not cap then
      return nil, ("the bag has %d arrays and the game has five pockets")
                  :format(#bag.capacities)
    end
    local n = held[name]
    if Gen3Save.POCKET_HOLDS_ALL[name] and n and n > cap then
      return nil, ("the %s array holds %d and this game has %d of them, so "
                   .. "the pocket order does not fit"):format(name, cap, n)
    end
  end
  return Gen3Save.POCKET_ORDER
end

-- The boxes.  Their shape is forced rather than chosen: one wallpaper byte per
-- box gives the box COUNT, the names divide by that count to give the name
-- length, and what is left over divides by the 80-byte boxed Pokemon to say
-- how many fit in a box.  Three constants out of the code and the storage size
-- from the sector layout decide all of it.
function Gen3Save.box(storage, index)
  local f = need("a box")
  local st = f.storage
  if not st or index < 1 or index > st.boxCount then return nil end
  local out = { index = index, wallpaper = u8(storage, st.boxWallpapers + index - 1),
                nameBytes = {} }
  local nameAt = st.boxNames + (index - 1) * st.boxNameLength
  for i = 0, st.boxNameLength - 1 do
    local b = u8(storage, nameAt + i)
    if b == 0xFF then break end
    out.nameBytes[#out.nameBytes + 1] = b
  end
  local base = st.boxes + (index - 1) * st.boxCapacity * st.boxMonSize
  for slot = 1, st.boxCapacity do
    local mon = Gen3Save.decodeBoxMon(storage, base + (slot - 1) * st.boxMonSize)
    if not mon.empty then
      mon.slot = slot
      out[#out + 1] = mon
    end
  end
  return out
end

function Gen3Save.currentBox(storage)
  local f = need("the current box")
  return f.storage and (u8(storage, f.storage.currentBox) + 1) or nil
end

-- ---------------------------------------------------------------------------
-- the crosswalk
--
-- A cartridge id is not this project's id.  Emerald numbers its species
-- internally in an order that is NOT the national dex -- 1..251 happen to
-- agree, then 25 slots are unused and the Hoenn species follow -- so a reader
-- that treats the stored number as a dex number gets every Hoenn Pokemon
-- wrong and no Johto one, which is exactly the kind of failure that looks like
-- it works.  The extractor stamps `index` on every species, move and item as
-- it reads them, and this turns that into a lookup both ways.
-- ---------------------------------------------------------------------------
local charmap = nil

function Gen3Save.setCharmap(map)
  charmap = map
end

local function byIndex(defs)
  local fromIndex, toIndex = {}, {}
  for id, def in pairs(defs or {}) do
    if type(def) == "table" and def.index ~= nil then
      fromIndex[def.index] = id
      toIndex[id] = def.index
    end
  end
  return fromIndex, toIndex
end

function Gen3Save.crosswalks(data)
  local pokemonByIndex, pokemonIndex = byIndex(data and data.pokemon)
  -- Pokedex bits use national numbers, while party and box records use the
  -- cartridge's internal species index. Keep this mapping separate so a
  -- save's dex flags are attached to the right species.
  local pokemonDex = {}
  for id, def in pairs((data and data.pokemon) or {}) do
    local dex = type(def) == "table" and tonumber(def.dex)
    if dex and dex >= 1 then pokemonDex[id] = math.floor(dex) end
  end
  local movesByIndex, movesIndex = byIndex(data and data.moves)
  local itemsByIndex, itemsIndex = byIndex(data and data.items)
  local mapsByGroupNumber, haveGroups = {}, false
  for id, def in pairs((data and data.maps) or {}) do
    if type(def) == "table" and def.group and def.number then
      mapsByGroupNumber[def.group * 256 + def.number] = id
      haveGroups = true
    end
  end
  -- which of the eight arrays a decoration belongs in, so the writer can pack
  -- each category's slots without needing a catalogue of its own
  local decorationCategory = {}
  do
    local r = data and data.constants and data.constants.gen3Decorations
    for _, def in ipairs((type(r) == "table" and r.list) or {}) do
      if type(def) == "table" and tonumber(def.id)
         and tonumber(def.category) then
        decorationCategory[math.floor(def.id)] = math.floor(def.category)
      end
    end
  end
  return { pokemonByIndex = pokemonByIndex, pokemonIndex = pokemonIndex,
           pokemonDex = pokemonDex,
           movesByIndex = movesByIndex, movesIndex = movesIndex,
           itemsByIndex = itemsByIndex, itemsIndex = itemsIndex,
           -- ...and the records themselves, because writing the bag back
           -- needs to know which POCKET each item goes in (gItems[].pocket)
           itemDefs = (data and data.items) or {},
           -- ...and the maps by id, for the other direction: decode turns a
           -- group and a number into a map id, and the writer has to turn one
           -- back
           mapDefs = (data and data.maps) or {},
           mapsByGroupNumber = mapsByGroupNumber, mapsHaveGroups = haveGroups,
           decorationCategory = decorationCategory,
           speciesDefs = (data and data.pokemon) or {} }
end

-- Names are the cartridge's own encoding.  A byte with no glyph is left as a
-- dot rather than dropped, so a name that fails to decode is visible instead
-- of silently shorter.
local function decodeText(bytes)
  if not charmap then return nil end
  local out = {}
  for _, b in ipairs(bytes) do
    out[#out + 1] = charmap[tostring(b)] or charmap[b] or "."
  end
  return table.concat(out)
end
Gen3Save.decodeText = decodeText

-- ...and the way back.  Built from the same charmap, restricted to the glyphs
-- that are ONE character, and taking the lowest byte for a glyph that has
-- several -- because Emerald's charmap holds ligatures (PK, MN, POKéBLOCK's
-- five) whose bytes are not letters, and a name written through one of them
-- comes back as a word the cartridge cannot render.
local encodeReverse = nil
local function encodeText(text, length, terminator)
  if not charmap then return nil end
  if not encodeReverse then
    encodeReverse = {}
    for code, glyph in pairs(charmap) do
      local n = tonumber(code)
      -- ONE character, counted in code points rather than bytes: "e" is one
      -- and so is the accented one, but "PK" and "OC" are two -- and those
      -- ligatures are exactly what a reverse map has to refuse, or a name
      -- with "BL" in it comes back one byte short and unreadable
      local letters = 0
      if type(glyph) == "string" then
        for _ in glyph:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
          letters = letters + 1
        end
      end
      if n and letters == 1
         and (encodeReverse[glyph] == nil or n < encodeReverse[glyph]) then
        encodeReverse[glyph] = n
      end
    end
  end
  local out, count = {}, 0
  for glyph in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if count >= (length or 0) then break end
    local code = encodeReverse[glyph]
    if code then
      out[#out + 1] = string.char(code)
      count = count + 1
    end
  end
  local pad = terminator or 0xFF
  while count < (length or 0) do
    out[#out + 1] = string.char(pad)
    count = count + 1
  end
  return table.concat(out)
end
Gen3Save.encodeText = encodeText

-- ---------------------------------------------------------------------------
-- THE MAUVILLE OLD MAN, and the eight decoration arrays.
--
-- The house east of Mauville's gym holds one of five men, chosen once from
-- the trainer id and then WRITTEN DOWN -- so a save that has been played
-- knows who lives there, and a reader that recomputes it would disagree with
-- the cartridge whenever the cartridge's own roll differed.  The block is
-- one id byte, then four decoration ids, four eleven-byte names, an
-- already-traded flag and four languages; the extractor derives its offset
-- off TraderDoDecorationTrade and proves it by the name slots ending exactly
-- where the flag begins.
--
-- The decorations themselves are eight fixed arrays that tile 150 bytes of
-- SaveBlock1, one id per slot with zero for empty -- which is why owning
-- three of a thing costs three slots.
-- ---------------------------------------------------------------------------
function Gen3Save.mauvilleMan(block1)
  local f = Gen3Save.fields
  local block = f and f.mauvilleMan
  if not (block and block.offset) then return nil end
  local at = block.offset
  local out = { man = u8(block1, at), trader = { decorations = {}, names = {} } }
  for i = 0, block.slots - 1 do
    out.trader.decorations[i + 1] = u8(block1, at + block.decorations + i)
    local bytes = {}
    for j = 0, block.nameBytes - 1 do
      local b = u8(block1, at + block.names + i * block.nameBytes + j)
      if b == 0xFF then break end
      bytes[#bytes + 1] = b
    end
    out.trader.names[i + 1] = decodeText(bytes) or ""
  end
  out.trader.traded = u8(block1, at + block.alreadyTraded) ~= 0
  return out
end

-- ---------------------------------------------------------------------------
-- THE TRENDY SAYINGS, which are a bitfield and not a list.
--
-- Thirty-three easy-chat words that start LOCKED. The HIPSTER in Mauville
-- opens one per conversation, at random, out of the ones you do not know --
-- so how many a save has is a record of how many times its player talked to
-- one man, and it is not recoverable from anything else in the file.
--
-- This port keeps them as `save.gen3TrendyPhrases[index] = true`, indexed from
-- zero the way the cartridge's own picker indexes them, because that is the
-- shape EasyChat.knowsPhrase already asks for. Bit n of byte floor(n/8), low
-- bit first, is where the cartridge puts them.
function Gen3Save.trendyPhrases(block1)
  local f = Gen3Save.fields
  local field = f and f.trendyPhrases
  if not (field and field.offset and field.count) then return nil end
  local out, any = {}, false
  for i = 0, field.count - 1 do
    local byte = u8(block1, field.offset + math.floor(i / 8)) or 0
    if math.floor(byte / 2 ^ (i % 8)) % 2 == 1 then
      out[i] = true
      any = true
    end
  end
  return any and out or nil
end

-- What the player owns, as the counts this port keeps: one id per slot in the
-- cartridge, so three of a thing arrive as three slots and leave as a count
-- of three.
function Gen3Save.decorations(block1)
  local f = Gen3Save.fields
  local caps = f and f.decorations
  if type(caps) ~= "table" or #caps == 0 then return nil end
  local out = {}
  for _, row in ipairs(caps) do
    for i = 0, row.size - 1 do
      local id = u8(block1, row.offset + i)
      if id and id > 0 then out[id] = (out[id] or 0) + 1 end
    end
  end
  return out
end


-- ---------------------------------------------------------------------------
-- writing
--
-- The rule here is PATCH, never rebuild.  A SaveBlock1 has hundreds of fields
-- and this project models a few dozen of them; rebuilding one from what it
-- models would silently blank the Pokedex, the Battle Frontier records, the
-- decorations, the secret base, the mail -- everything it does not know about.
-- So a write starts from the save that was read, changes only the bytes whose
-- field changed, and re-derives the three things that must follow: each
-- Pokemon's checksum, each sector's checksum, and the slot counter.
--
-- And it writes into the OTHER slot.  That is what the cartridge does, and it
-- is not a detail: writing over the slot that was just read leaves no intact
-- copy if the write is interrupted, which is the exact failure the two-slot
-- design exists to prevent.
-- ---------------------------------------------------------------------------
local function put(str, off, bytes)
  return str:sub(1, off) .. bytes .. str:sub(off + #bytes + 1)
end
local function b8(v) return string.char(v % 256) end
local function b16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function b32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
                     math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local function arrayFlag(bytes, base, bitIndex)
  if not (bytes and base and bitIndex and bitIndex >= 0) then return false end
  local byte = u8(bytes, base + math.floor(bitIndex / 8))
  return math.floor(byte / (2 ^ (bitIndex % 8))) % 2 == 1
end

local function setArrayFlag(bytes, base, bitIndex, value)
  if not (bytes and base and bitIndex and bitIndex >= 0) then return bytes end
  local offset = base + math.floor(bitIndex / 8)
  local mask = 2 ^ (bitIndex % 8)
  local byte = u8(bytes, offset)
  local has = math.floor(byte / mask) % 2 == 1
  value = value and true or false
  if has == value then return bytes end
  return put(bytes, offset, b8(value and (byte + mask) or (byte - mask)))
end

-- FireRed's dex calls use one-based National Dex numbers; its packed arrays
-- start at zero, so number N maps to bit N-1, least-significant bit first.
local function dexFlag(bytes, base, dexNumber)
  if not (dexNumber and dexNumber >= 1) then return false end
  return arrayFlag(bytes, base, dexNumber - 1)
end

local function setDexFlag(bytes, base, dexNumber, value)
  if not (dexNumber and dexNumber >= 1) then return bytes end
  return setArrayFlag(bytes, base, dexNumber - 1, value)
end

local function readPokedex(blocks, cw)
  local out = { seen = {}, owned = {} }
  local f = Gen3Save.fields or {}
  local pdx = (f.saveBlock2 or {}).pokedex
  local s1 = f.saveBlock1 or {}
  local count = pdx and tonumber(pdx.flagBytes)
  if not (count and count > 0 and pdx.owned and pdx.seen
          and s1.pokedexSeen1 and s1.pokedexSeen2) then
    return out
  end

  for species, dexNumber in pairs(cw.pokemonDex or {}) do
    if dexNumber <= count * 8 then
      local seen = dexFlag(blocks.block2, pdx.seen, dexNumber)
        and dexFlag(blocks.block1, s1.pokedexSeen1, dexNumber)
        and dexFlag(blocks.block1, s1.pokedexSeen2, dexNumber)
      if seen then
        out.seen[species] = true
        if dexFlag(blocks.block2, pdx.owned, dexNumber) then
          out.owned[species] = true
        end
      end
    end
  end
  return out
end

local function writePokedex(blocks, save, cw)
  local f = Gen3Save.fields or {}
  local pdx = (f.saveBlock2 or {}).pokedex
  local s1 = f.saveBlock1 or {}
  local b1, b2 = blocks.block1, blocks.block2

  if pdx and type(save.pokedex) == "table" and pdx.flagBytes
     and pdx.owned and pdx.seen and s1.pokedexSeen1 and s1.pokedexSeen2 then
    local count = math.floor(tonumber(pdx.flagBytes) or 0)
    local dexSeen, dexOwned = {}, {}
    for species, dexNumber in pairs(cw.pokemonDex or {}) do
      if dexNumber <= count * 8 then
        local owned = (save.pokedex.owned or {})[species] and true or false
        -- A caught Pokemon must also be registered as seen, matching the
        -- cartridge's GetSetPokedexFlag behavior.
        local seen = owned or ((save.pokedex.seen or {})[species] and true or false)
        dexSeen[dexNumber] = dexSeen[dexNumber] or seen
        dexOwned[dexNumber] = dexOwned[dexNumber] or owned
      end
    end
    -- Patch only national numbers the loaded ROM data knows about. This
    -- preserves reserved bits and any entries from a newer/extended cache.
    for dexNumber in pairs(dexSeen) do
      local owned = dexOwned[dexNumber] and true or false
      local seen = owned or (dexSeen[dexNumber] and true or false)
      b2 = setDexFlag(b2, pdx.owned, dexNumber, owned)
      b2 = setDexFlag(b2, pdx.seen, dexNumber, seen)
      b1 = setDexFlag(b1, s1.pokedexSeen1, dexNumber, seen)
      b1 = setDexFlag(b1, s1.pokedexSeen2, dexNumber, seen)
    end
  end

  -- FireRed requires all three pieces of its National Dex unlock state. The
  -- game never revokes this upgrade, so only stamp it when the port has
  -- unlocked it; otherwise the untouched template bytes remain intact.
  if pdx and save.nationalDex == true and pdx.nationalMagic
     and pdx.nationalMagicValue and pdx.nationalFlagId and pdx.nationalVarId
     and pdx.nationalVarValue and s1.flags and s1.vars then
    b2 = put(b2, pdx.nationalMagic, b8(pdx.nationalMagicValue))
    local flag = tonumber(pdx.nationalFlagId)
    if flag and flag > 0 then b1 = setArrayFlag(b1, s1.flags, flag, true) end
    local varId = tonumber(pdx.nationalVarId)
    local base = tonumber(f.varsStartId) or 0x4000
    local varCount = tonumber(f.varCount) or 0
    local varIndex = varId and (varId - base) or -1
    if varIndex >= 0 and varIndex < varCount then
      b1 = put(b1, s1.vars + varIndex * 2, b16(pdx.nationalVarValue))
    end
  end
  return b1, b2
end

-- One Pokemon, patched in place: decrypt the 48 secure bytes, change only what
-- was asked for, re-checksum over the PLAIN bytes and re-encrypt.  The
-- checksum is over the decrypted form, so encrypting first and checksumming
-- after produces a Pokemon the game treats as a bad egg.
function Gen3Save.patchBoxMon(bytes, off, changes)
  local orders = Gen3Save.substructOrders
  if not orders then error("Gen3Save: no substructure orders (setLayout first)") end
  local personality = u32(bytes, off)
  local otId = u32(bytes, off + 4)
  local key = xorU32(personality, otId)

  local plain = {}
  for i = 0, Gen3Save.SECURE_SIZE / 4 - 1 do
    local w = xorU32(u32(bytes, off + Gen3Save.SECURE_OFFSET + i * 4), key)
    for k = 0, 3 do
      plain[i * 4 + k + 1] = math.floor(w / 256 ^ k) % 256
    end
  end

  local order = orders[(personality % 24) + 1]
  local slotOf = {}
  for k = 1, 4 do slotOf[Gen3Save.SUBSTRUCTS[k]] = order[k] * Gen3Save.SUBSTRUCT_SIZE end
  local function setU16(which, at, v)
    local i = slotOf[which] + at
    plain[i + 1] = v % 256
    plain[i + 2] = math.floor(v / 256) % 256
  end
  local function setU8(which, at, v) plain[slotOf[which] + at + 1] = v % 256 end
  local function setU32(which, at, v)
    for k = 0, 3 do plain[slotOf[which] + at + k + 1] = math.floor(v / 256 ^ k) % 256 end
  end

  if changes.species then setU16("growth", 0, changes.species) end
  if changes.heldItem then setU16("growth", 2, changes.heldItem) end
  if changes.experience then setU32("growth", 4, changes.experience) end
  if changes.friendship then setU8("growth", 9, changes.friendship) end
  if changes.moves then
    for i = 1, 4 do
      if changes.moves[i] then setU16("attacks", (i - 1) * 2, changes.moves[i]) end
    end
  end
  if changes.pp then
    for i = 1, 4 do
      if changes.pp[i] then setU8("attacks", 8 + i - 1, changes.pp[i]) end
    end
  end
  if changes.evs then
    local ORDER = { "hp", "attack", "defense", "speed", "spAttack", "spDefense" }
    for i, k in ipairs(ORDER) do
      if changes.evs[k] then setU8("evs", i - 1, changes.evs[k]) end
    end
  end
  if changes.ppBonuses then setU8("growth", 8, changes.ppBonuses) end
  -- ...AND THE REST OF MISC AND EVS, which a patch never needed and a record
  -- built from nothing cannot do without: where it was met, what it was
  -- caught in, and the five contest numbers that sit behind the EVs.
  if changes.contest then
    local ORDER = { "cool", "beauty", "cute", "smart", "tough", "sheen" }
    for i, k in ipairs(ORDER) do
      if changes.contest[k] then setU8("evs", 5 + i, changes.contest[k]) end
    end
  end
  if changes.pokerus then setU8("misc", 0, changes.pokerus) end
  if changes.metLocation then setU8("misc", 1, changes.metLocation) end
  if changes.origins then setU16("misc", 2, changes.origins) end
  if changes.ivWord then setU32("misc", 4, changes.ivWord) end

  local sum = 0
  for i = 0, Gen3Save.SECURE_SIZE / 2 - 1 do
    sum = (sum + plain[i * 2 + 1] + plain[i * 2 + 2] * 256) % 65536
  end
  local out = bytes
  out = put(out, off + 28, b16(sum))
  for i = 0, Gen3Save.SECURE_SIZE / 4 - 1 do
    local w = plain[i * 4 + 1] + plain[i * 4 + 2] * 256
              + plain[i * 4 + 3] * 65536 + plain[i * 4 + 4] * 16777216
    out = put(out, off + Gen3Save.SECURE_OFFSET + i * 4, b32(xorU32(w, key)))
  end
  return out
end

-- What this project models of a Pokemon, in the shape patchBoxMon takes.  The
-- party writer and the box writer both need it and must agree: a mon deposited
-- from the party has to come out of the box the same Pokemon it went in as.
local function boxChanges(mon, cw)
  local changes = { friendship = mon.happiness, experience = mon.exp }
  if cw and mon.species then changes.species = cw.pokemonIndex[mon.species] end
  if cw and mon.item then changes.heldItem = cw.itemsIndex[mon.item] end
  if mon.moves then
    changes.moves, changes.pp = {}, {}
    for k, mv in ipairs(mon.moves) do
      changes.moves[k] = cw and cw.movesIndex[mv.id] or nil
      changes.pp[k] = mv.pp
    end
  end
  if mon.evs then
    changes.evs = { hp = mon.evs.hp, attack = mon.evs.attack,
                    defense = mon.evs.defense, speed = mon.evs.speed,
                    spAttack = mon.evs.spatk, spDefense = mon.evs.spdef }
  end
  if mon.contest then
    changes.contest = { cool = mon.contest.cool, beauty = mon.contest.beauty,
                        cute = mon.contest.cute, smart = mon.contest.smart,
                        tough = mon.contest.tough, sheen = mon.contest.sheen }
  end
  if mon.gen3Pokerus then changes.pokerus = mon.gen3Pokerus end
  -- PP UPS are two bits a move in one byte, so they are rebuilt from the four
  -- moves together rather than patched one at a time
  if mon.moves then
    local bonuses, any = 0, false
    for k, mv in ipairs(mon.moves) do
      if k <= 4 and mv.ppUps and mv.ppUps > 0 then
        bonuses = bonuses + (math.min(3, mv.ppUps) * 4 ^ (k - 1))
        any = true
      end
    end
    if any then changes.ppBonuses = bonuses end
  end
  return changes
end

-- ...and the fields a PATCH never has to supply because the record already
-- carries them, which a record built from nothing does.  Kept apart from
-- boxChanges so that patching a real cartridge record still touches only what
-- this project actually models: writing a met location onto a Pokemon that
-- came off a cartridge would replace a real one with this port's guess.
local function boxOrigins(mon, cw)
  local out = {}
  if mon.metLocation then out.metLocation = math.floor(mon.metLocation) end
  out.origins = Gen3Save.packOrigins({
    metLevel = mon.metLevel or mon.level,
    -- the game of origin: EMERALD is what a Pokemon caught in this port was
    -- caught in, and the number is the one the import reads back out of the
    -- same field (unpackOrigins) rather than a new claim
    metGame = mon.gen3MetGame or Gen3Save.defaultMetGame
              or Gen3Save.MET_GAME_EMERALD,
    ball = (cw and mon.ball and cw.itemsIndex[mon.ball]) or nil,
    otFemale = mon.gen3OtFemale,
  })
  out.ivWord = Gen3Save.packIVs({
    hp = (mon.ivs or {}).hp, attack = (mon.ivs or {}).attack,
    defense = (mon.ivs or {}).defense, speed = (mon.ivs or {}).speed,
    spAttack = (mon.ivs or {}).spatk, spDefense = (mon.ivs or {}).spdef,
    isEgg = mon.isEgg, altAbility = mon.altAbility,
  })
  return out
end

-- BUILDING A RECORD RATHER THAN MOVING ONE.
--
-- The box writer relocates the eighty bytes a Pokemon ARRIVED in, because
-- those bytes carry more than this project models.  A Pokemon that never
-- arrived -- caught in this port, in a save that was never imported -- has no
-- such bytes, and until now that meant it could not be written at all: its
-- slot was left empty and it was named in `unwritable`.  For a save built from
-- nothing that is EVERY Pokemon, which is an export with no party in it.
--
-- So the record is built.  What goes in it is the port's own fields plus the
-- two things structure forces:
--
--   * THE PERSONALITY MUST NOT BE ZERO.  It keys the encryption, the
--     substructure order, the nature, the ability slot and the gender, and a
--     record whose personality and trainer id are both zero is what this
--     codec's own reader calls an empty slot.  A Gen 3 Pokemon made by this
--     port already has one; a Pokemon carried over from a Gen 1 or Gen 2 save
--     does not, and gets one derived from what it IS -- species, level and
--     owner -- so that the same save exported twice is the same bytes rather
--     than a new Pokemon each time.
--   * HAS_SPECIES MUST BE SET.  The cartridge reads that one bit before it
--     reads anything else; a complete record with it clear is an empty slot.
--
-- The trainer is the PLAYER unless the Pokemon names its own -- which is what
-- makes a traded Pokemon still somebody else's, and what makes shininess come
-- out the same here as it does in the port.
function Gen3Save.buildBoxMon(mon, cw, owner)
  owner = owner or {}
  local personality = math.floor(tonumber(mon.personality) or 0)
  local publicId = math.floor(tonumber(mon.otId) or tonumber(owner.id) or 0) % 65536
  local secretId = math.floor(tonumber(mon.secretId)
                              or tonumber(owner.secretId) or 0) % 65536
  local otId = secretId * 65536 + publicId
  if personality <= 0 then
    -- DERIVED, NOT ROLLED.  A random one would make every export of the same
    -- save a different Pokemon -- different nature, different ability,
    -- different gender -- and two exports of one save have to match.  The
    -- species and the owner are what this Pokemon is; the odd multiplier is
    -- only there to spread neighbouring species across the 24 substructure
    -- orders instead of lining them all up on the same one.
    local index = (cw and mon.species and cw.pokemonIndex[mon.species]) or 0
    personality = ((index * 2654435761)
                   + (math.floor(tonumber(mon.level) or 0) * 40503)
                   + otId) % 4294967296
    if personality == 0 then personality = 1 end
  end

  local defaults = owner.defaults or {}
  local nickname = mon.nickname
  if not nickname or nickname == "" then
    -- the species' own name, which is what the cartridge puts in an
    -- un-nicknamed record: a blank one shows as blanks, not as the species
    local def = cw and cw.speciesDefs and cw.speciesDefs[mon.species]
    nickname = (def and (def.translationSourceName or def.name)) or tostring(mon.species or "")
  end
  local otName = mon.gen3OtName or owner.name or ""
  local flags = Gen3Save.MON_HAS_SPECIES
  if mon.isEgg then flags = flags + Gen3Save.MON_IS_EGG end

  local record = b32(personality) .. b32(otId)
    .. (encodeText(nickname, Gen3Save.NICKNAME_LENGTH)
        or string.rep("\255", Gen3Save.NICKNAME_LENGTH))
    .. b8(math.floor(tonumber(mon.gen3Language)
                     or defaults.language or Gen3Save.LANGUAGE_ENGLISH))
    .. b8(flags)
    .. (encodeText(otName, Gen3Save.OT_NAME_LENGTH)
        or string.rep("\255", Gen3Save.OT_NAME_LENGTH))
    .. b8(math.floor(tonumber(mon.gen3Markings) or 0))
    .. b16(0) .. b16(0)
    .. string.rep("\0", Gen3Save.SECURE_SIZE)

  local changes = boxChanges(mon, cw)
  for k, v in pairs(boxOrigins(mon, cw)) do changes[k] = v end
  if changes.origins == nil or mon.gen3MetGame == nil then
    changes.origins = Gen3Save.packOrigins({
      metLevel = mon.metLevel or mon.level,
      metGame = mon.gen3MetGame or defaults.metGame
                or Gen3Save.defaultMetGame or Gen3Save.MET_GAME_EMERALD,
      ball = (cw and mon.ball and cw.itemsIndex[mon.ball]) or nil,
      otFemale = mon.gen3OtFemale,
    })
  end
  return Gen3Save.patchBoxMon(record, 0, changes)
end

-- Apply a decoded-and-edited save table back onto the blocks it came from.
-- Only fields this project models are touched; everything else is left exactly
-- as the cartridge wrote it.
function Gen3Save.applyBlocks(blocks, save, cw)
  local f = need("a write")
  local b1, b2 = blocks.block1, blocks.block2
  local key = Gen3Save.encryptionKey(b2)
  local s1, s2 = f.saveBlock1, f.saveBlock2

  if save.money then b1 = put(b1, s1.money, b32(xorU32(save.money, key))) end
  if save.coins then
    b1 = put(b1, s1.coins, b16(xorU32(save.coins, key) % 65536))
  end
  if save.berryPowder and s2.berryPowder then
    b2 = put(b2, s2.berryPowder, b32(xorU32(save.berryPowder, key)))
  end
  -- Battle Points go back plain, and CLAMPED to the cartridge's own cap: the
  -- adder stops at it, so a file carrying more than it could ever have earned
  -- is one this port wrote and not one the cartridge would.
  if save.gen3BattlePoints and s2.battlePoints then
    local cap = tonumber(f.battlePointsCap) or 9999
    local n = math.floor(tonumber(save.gen3BattlePoints) or 0)
    b2 = put(b2, s2.battlePoints, b16(math.max(0, math.min(cap, n))))
  end
  if type(save.gen3DewfordTrend) == "table" and s1.dewfordTrend then
    b1 = put(b1, s1.dewfordTrend,
             b16(math.floor(save.gen3DewfordTrend[1] or 0) % 65536)
             .. b16(math.floor(save.gen3DewfordTrend[2] or 0) % 65536))
  end
  -- The game statistics go back the way flags do: EVERY counter is written,
  -- not only the ones the run touched, because a counter this engine has no
  -- name for still has to survive the round trip rather than come back zero.
  if type(save.gen3Stats) == "table" and s1.gameStats and s1.gameStatCount then
    for i = 0, math.floor(s1.gameStatCount) - 1 do
      local value = math.floor(tonumber(save.gen3Stats[i]) or 0)
      b1 = put(b1, s1.gameStats + i * 4, b32(xorU32(value, key)))
    end
  end
  if save.playTime then
    local t = math.max(0, save.playTime)
    local hours = math.floor(t / 3600)
    local minutes = math.floor(t % 3600 / 60)
    local seconds = math.floor(t % 60)
    b2 = put(b2, s2.playTimeHours, b16(math.min(hours, 65535)))
    b2 = put(b2, s2.playTimeMinutes, b8(minutes) .. b8(seconds))
  end

  -- Flags are a bit array, so a flag that went FALSE has to be cleared rather
  -- than merely not set: writing only the true ones leaves every flag the
  -- player has undone still set, and the scripts would replay as if nothing
  -- had been reversed.
  if save.flags then
    local bytes = {}
    for i = 0, f.flagBytes - 1 do bytes[i] = u8(b1, s1.flags + i) end
    for id = 1, f.flagBytes * 8 - 1 do
      local name = ("FLAG_G3_%04X"):format(id)
      local want = save.flags[name] and true or false
      local i, bit = math.floor(id / 8), 2 ^ (id % 8)
      local has = math.floor(bytes[i] / bit) % 2 == 1
      if want ~= has then bytes[i] = bytes[i] + (want and bit or -bit) end
    end
    local out = {}
    for i = 0, f.flagBytes - 1 do out[i + 1] = string.char(bytes[i]) end
    b1 = put(b1, s1.flags, table.concat(out))
  end

  -- Variables, and ONLY the ones this project has an answer for.
  --
  -- This used to write `save.gen3Vars[id] or 0` across all 256, which reads as
  -- harmless and is not: a var the port has never modelled came back as zero,
  -- so exporting a save that had not been imported wiped the whole block.  The
  -- rotating gates are the clearest casualty -- their orientations are one
  -- byte each in the vars from $4000, so every gate in Fortree's gym and the
  -- Trick House would spring back to where it started -- but it is every
  -- unmodelled var, and there is no way to tell afterwards.
  --
  -- A var the port DID set to zero still writes: nil and 0 are different
  -- things here, and only nil means "nothing to say".
  if save.gen3Vars then
    local base = f.varsStartId or 0x4000
    for i = 0, (f.varCount or 0) - 1 do
      local v = save.gen3Vars[base + i]
      if v ~= nil then b1 = put(b1, s1.vars + i * 2, b16(v % 65536)) end
    end
  end

  b1, b2 = writePokedex({ block1 = b1, block2 = b2 }, save, cw)

  -- The berry trees, written back the same eight bytes they were read from.
  --
  -- Only the plots the port has an answer for: a tree the engine never touched
  -- keeps whatever the cartridge put there, the same rule the variables above
  -- follow.  An EMPTY plot is an answer -- the player picked it and it died --
  -- so a record present in save.gen3BerryTrees with no berry is written as
  -- eight zero bytes rather than skipped.
  if save.gen3BerryTrees and f.berryTrees then
    local block = f.berryTrees
    for i = 0, block.count - 1 do
      local tree = save.gen3BerryTrees[i]
      if type(tree) == "table" then
        local at = block.offset + i * block.stride
        local berry = math.floor(tonumber(tree.berry) or 0) % 256
        local stage = math.floor(tonumber(tree.stage) or 0) % 128
        local packed = stage + (tree.stopGrowth and 128 or 0)
        local flags = math.floor(tonumber(tree.regrowth) or 0) % 16
        for w, bit in ipairs(BERRY_WATER_BITS) do
          if tree.watered and tree.watered[w] then flags = flags + bit end
        end
        b1 = put(b1, at, string.char(berry, packed))
        b1 = put(b1, at + 2, b16(math.floor(tonumber(tree.minutes) or 0) % 65536))
        b1 = put(b1, at + 4,
                 string.char(math.floor(tonumber(tree.yield) or 0) % 256, flags))
      end
    end
  end

  -- The Mauville old man, and the decoration arrays.
  --
  -- The man's ID is written back too, because a save this port started rolled
  -- it from the trainer id and the cartridge would otherwise read a zero as
  -- "the Bard".  The names are re-encoded through the charmap and padded with
  -- $FF, which is the terminator every other name in the file uses.
  if save.gen3MauvilleMan and f.mauvilleMan then
    local block = f.mauvilleMan
    local state = save.gen3MauvilleMan
    local at = block.offset
    b1 = put(b1, at, b8(math.floor(tonumber(state.man) or 0) % 256))
    local trader = type(state.trader) == "table" and state.trader or nil
    if trader then
      for i = 0, block.slots - 1 do
        local id = math.floor(tonumber((trader.decorations or {})[i + 1]) or 0)
        b1 = put(b1, at + block.decorations + i, b8(id % 256))
        local name = encodeText((trader.names or {})[i + 1], block.nameBytes)
        if name then
          b1 = put(b1, at + block.names + i * block.nameBytes, name)
        end
      end
      b1 = put(b1, at + block.alreadyTraded, b8(trader.traded and 1 or 0))
    end
  end

  -- The trendy sayings go back as the bitfield they came from. Written whole
  -- rather than or-ed into what is there: a saying this port has NOT recorded
  -- has to come out locked, or a round trip through the editor could only ever
  -- add to them.
  if save.gen3TrendyPhrases and f.trendyPhrases then
    local field = f.trendyPhrases
    for byte = 0, field.bytes - 1 do
      local value = 0
      for bit = 0, 7 do
        local index = byte * 8 + bit
        if index < field.count and save.gen3TrendyPhrases[index] then
          value = value + 2 ^ bit
        end
      end
      b1 = put(b1, field.offset + byte, b8(value))
    end
  end

  -- Decorations go back one id per slot, packed to the front of each
  -- category's array with the rest zeroed -- which is what the cartridge's own
  -- GetFirstEmptyDecorSlot expects to find.  A count past the cap is dropped
  -- rather than allowed to run into the next category.
  if save.gen3 and save.gen3.decorations and f.decorations then
    local byCategory = {}
    for id, n in pairs(save.gen3.decorations) do
      local count = (n == true) and 1 or math.floor(tonumber(n) or 0)
      local category = (cw.decorationCategory or {})[id] or 0
      if count > 0 and type(id) == "number" then
        byCategory[category] = byCategory[category] or {}
        for _ = 1, count do
          byCategory[category][#byCategory[category] + 1] = id
        end
      end
    end
    for _, row in ipairs(f.decorations) do
      local list = byCategory[row.category] or {}
      for i = 0, row.size - 1 do
        b1 = put(b1, row.offset + i, b8(math.floor(list[i + 1] or 0) % 256))
      end
    end
  end

  -- EVERY RECORD THIS SAVE ALREADY HOLDS, FOUND BEFORE ANYTHING IS WRITTEN.
  --
  -- A Pokemon is identified by its personality and its trainer id together --
  -- the pair that keys its substructure order, its shininess and its
  -- encryption on the cartridge as much as here -- and the commonest edit of
  -- all, depositing, MOVES a record from the party into a box.  So the map is
  -- taken in one pass over both before a single byte changes, or a deposit
  -- would look for its original in a slot that has already been overwritten.
  --
  -- It was built inside the box writer and the party writer could not see it,
  -- which did not matter while the party was only ever patched in place.  It
  -- matters now: a party slot in a save built from NOTHING holds zeros, and
  -- patching zeros produces a Pokemon whose personality and trainer id are
  -- both zero -- which this codec's own reader calls an empty slot.
  local origins = {}
  do
    local function remember(source, at)
      if not source then return end
      local mon = Gen3Save.decodeBoxMon(source, at)
      if not mon.empty then
        local key = ("%d:%d"):format(mon.personality, mon.otId)
        origins[key] = origins[key]
          or source:sub(at + 1, at + Gen3Save.BOX_MON_SIZE)
      end
    end
    if f.party then
      for i = 1, f.party.size do
        remember(blocks.block1, f.party.start + (i - 1) * f.party.monSize)
      end
    end
    if f.storage and blocks.storage then
      local sst = f.storage
      for b = 1, sst.boxCount do
        local base = sst.boxes + (b - 1) * sst.boxCapacity * sst.boxMonSize
        for slot = 1, sst.boxCapacity do
          remember(blocks.storage, base + (slot - 1) * sst.boxMonSize)
        end
      end
    end
  end
  local function originOf(mon)
    if not (mon and mon.personality and mon.otId) then return nil end
    return origins[("%d:%d"):format(mon.personality,
                                    (mon.secretId or 0) * 65536 + mon.otId)]
  end
  -- who a Pokemon with no trainer of its own belongs to, and what language a
  -- Pokemon with no language of its own is written in
  local owner = {
    id = save.player and save.player.id,
    secretId = save.player and save.player.secretId,
    name = save.player and save.player.name,
    defaults = Gen3Save.saveDefaults(blocks),
  }

  -- The party.  A slot whose Pokemon came off a cartridge is PATCHED -- the
  -- record keeps its nickname, its original trainer, where it was met and its
  -- ribbons, none of which this project models and all of which a rebuild
  -- would erase.  One that did not is BUILT (see buildBoxMon), which is what
  -- lets a playthrough that never touched a cartridge export a party at all.
  if save.party and f.party then
    b1 = put(b1, f.party.count, b8(math.min(#save.party, f.party.size)))
    local blank = string.rep("\0", f.party.monSize)
    for i = 1, f.party.size do
      local mon = save.party[i]
      local at = f.party.start + (i - 1) * f.party.monSize
      if mon == nil then
        b1 = put(b1, at, blank)
      else
        local from = originOf(mon)
        if from then
          b1 = put(b1, at, from)
          b1 = Gen3Save.patchBoxMon(b1, at, boxChanges(mon, cw))
        else
          b1 = put(b1, at, Gen3Save.buildBoxMon(mon, cw, owner)
                           .. string.rep("\0", f.party.monSize
                                               - Gen3Save.BOX_MON_SIZE))
          -- THE FIVE COMPUTED STATS, which only a party record carries and
          -- only a built one has to supply: a relocated record already has
          -- them, and the cartridge recomputes them at the next level.  Left
          -- at zero a freshly exported party is six Pokemon with no Attack.
          local st5 = mon.stats or {}
          local ORDER = { st5.attack, st5.defense, st5.speed,
                          st5.spatk or st5.spAttack,
                          st5.spdef or st5.spDefense }
          for k, v in ipairs(ORDER) do
            b1 = put(b1, at + 88 + k * 2,
                     b16(math.max(0, math.min(65535, math.floor(v or 0)))))
          end
        end
        if mon.statusWord then b1 = put(b1, at + 80, b32(mon.statusWord)) end
        if mon.level then b1 = put(b1, at + 84, b8(mon.level)) end
        if mon.hp then b1 = put(b1, at + 86, b16(mon.hp)) end
        if mon.maxHp then b1 = put(b1, at + 88, b16(mon.maxHp)) end
      end
    end
  end

  -- ---------------------------------------------------------------------
  -- THE BOXES, which were not written back at all.
  --
  -- `decode` reads them; nothing wrote them, so the storage came back out of
  -- here exactly as the cartridge wrote it and every change the player made in
  -- the PC was discarded on export.  Deposit a Pokemon and the exported save
  -- still had it in the party and not in the box.
  --
  -- A BOX RECORD CANNOT BE REBUILT, ONLY MOVED.  Eighty bytes hold far more
  -- than this project models -- the nickname, the original trainer and their
  -- language, where it was met, its ribbons -- and none of that is on the
  -- engine's Pokemon.  So a slot is not written from the engine's fields; the
  -- record the mon ARRIVED in is found again and relocated, and only then
  -- patched with what changed.  A Pokemon is identified by its personality
  -- and its trainer id together, which is what makes it that Pokemon on the
  -- cartridge as well: the pair is what keys its substructure order, its
  -- shininess and its encryption.
  --
  -- The originals are read from the party AND the boxes before anything is
  -- written, because the commonest edit of all -- depositing -- moves a record
  -- from one to the other, and a snapshot taken as we go would find a slot
  -- already overwritten.
  --
  -- A Pokemon with no original is one that was CAUGHT IN THE PORT, and this
  -- cannot write it: patchBoxMon derives its key from a personality and
  -- trainer id that are already in the bytes, so there is nothing to patch. It
  -- is named in `unwritable` rather than being invented, and its slot is left
  -- empty -- an empty slot is a save that loads, and a fabricated record is
  -- one that may not.
  local unwritable = nil
  local storage = blocks.storage
  local st = f.storage
  if save.boxes and st and storage then
    -- the same map the party writer used, taken once above -- a deposit moves
    -- a record from one to the other and both have to look in the same place
    local empty = string.rep("\0", st.boxMonSize)
    for b = 1, st.boxCount do
      local box = save.boxes[b] or {}
      local base = st.boxes + (b - 1) * st.boxCapacity * st.boxMonSize
      for slot = 1, st.boxCapacity do
        local at = base + (slot - 1) * st.boxMonSize
        local mon = box[slot]
        local from = mon and originOf(mon)
        if mon == nil then
          storage = put(storage, at, empty)
        elseif from then
          storage = put(storage, at, from)
          storage = Gen3Save.patchBoxMon(storage, at, boxChanges(mon, cw))
        else
          -- ...and one that never came off a cartridge is BUILT, the same way
          -- the party's are.  It used to be left empty and reported, which was
          -- the right answer while a record could only be moved and never
          -- made -- and which emptied every box of a save written from
          -- nothing.
          storage = put(storage, at, Gen3Save.buildBoxMon(mon, cw, owner))
        end
      end
      if box.wallpaper then
        storage = put(storage, st.boxWallpapers + b - 1, b8(box.wallpaper))
      end
      -- ...AND ITS NAME, which decode reads and nothing wrote.  Renaming a box
      -- in the port was discarded on export, and on a save built from nothing
      -- every one of the fourteen would have come out blank.
      if box.name and st.boxNames and st.boxNameLength then
        local named = encodeText(box.name, st.boxNameLength)
        if named then
          storage = put(storage, st.boxNames + (b - 1) * st.boxNameLength,
                        named)
        end
      end
    end
    if save.currentBox then
      storage = put(storage, st.currentBox, b8(save.currentBox - 1))
    end
  end

  -- ---- WHO THE PLAYER IS ------------------------------------------------
  --
  -- Read by decode and never written, which mattered nothing while an export
  -- could only ever be written onto the cartridge image it came from -- the
  -- name was already in it.  A save built from NOTHING has eight zero bytes
  -- there, and zero is a SPACE in this cartridge's charmap, so the trainer
  -- card would have read as eight spaces and the trainer id as 00000.
  --
  -- The name is padded with the terminator rather than with spaces, which is
  -- what makes a four-letter name four letters long on the card instead of an
  -- eight-wide field with a name at one end.
  -- eight, which is the gap the layout leaves between playerName and
  -- playerGender and the same eight playerNameBytes reads back
  local nameLen = (s2.playerGender and s2.playerName
                   and (s2.playerGender - s2.playerName)) or 8
  if type(save.player) == "table" then
    if save.player.name then
      local bytes = encodeText(save.player.name, nameLen)
      if bytes then b2 = put(b2, s2.playerName, bytes) end
    end
    if save.player.gender then
      b2 = put(b2, s2.playerGender,
               b8(save.player.gender == "girl" and 1 or 0))
    end
    -- THE TWO HALVES OF THE TRAINER ID ARE ONE WORD, and the secret half is
    -- the one nobody sees: it decides shininess and it is what a traded
    -- Pokemon is checked against, so a save that dropped it would turn every
    -- Pokemon the player owns into somebody else's.
    if save.player.id then
      b2 = put(b2, s2.playerTrainerId,
               b16(math.floor(save.player.id) % 65536)
               .. b16(math.floor(save.player.secretId or 0) % 65536))
    end
  end

  -- ---- WHERE THE PLAYER IS STANDING, WHICH NOTHING WROTE EITHER ---------
  --
  -- `decode` reads three numbers out of the save -- the map's group and
  -- number out of SaveBlock1's WarpData, and the coordinates out of the
  -- Coords16 at the front of the block -- and nothing put any of them back.
  -- An exported save dropped the player wherever the CARTRIDGE was standing
  -- when it was imported, however far they had walked since.
  --
  -- Written only when the map resolves to a group and a number this cartridge
  -- knows, for the same reason decode refuses the other way: a map this port
  -- invented has no pair to write, and writing a wrong one puts the player
  -- inside a map that does not exist.
  --
  -- THE WARP ID IS LEFT ALONE.  WarpData carries one after the group and
  -- number, and a save made in the field holds -1 there -- "use the
  -- coordinates" -- which is exactly the state being written here.  Nothing
  -- in the import derives that byte, so it keeps whatever the cartridge put
  -- in it rather than being set from a guess.
  if type(save.player) == "table" and s1.location and cw.mapDefs then
    local def = save.player.map and cw.mapDefs[save.player.map]
    local group, number = def and tonumber(def.group), def and tonumber(def.number)
    if group and number then
      b1 = put(b1, s1.location, b8(group % 256) .. b8(number % 256))
      if s1.posX and save.player.x then
        b1 = put(b1, s1.posX, b16(math.floor(save.player.x) % 65536))
      end
      if s1.posY and save.player.y then
        b1 = put(b1, s1.posY, b16(math.floor(save.player.y) % 65536))
      end
    elseif save.player.map then
      unwritable = unwritable or {}
      unwritable[#unwritable + 1] =
        { what = "location", id = save.player.map,
          reason = "this map has no group and number on the cartridge, so "
                   .. "the saved position is left where it was" }
    end
  end

  -- ---- THE BAG, WHICH NOTHING WROTE AT ALL ------------------------------
  --
  -- Every other field here was at least attempted; the bag was not in this
  -- function, so an exported save came back carrying the items the CARTRIDGE
  -- had when it was imported and none of the ones earned since.  A player who
  -- imported a save, played to Dewford and exported got their potions,
  -- repels, Devon Goods and every berry picked on the way silently rolled
  -- back.
  --
  -- WRITTEN WHOLE, like the flags and the game statistics, and for the same
  -- reason: a slot that went EMPTY has to be cleared rather than merely not
  -- rewritten, or an item the player used up is still sitting in the bag.
  --
  -- The quantities go back through the key (see Gen3Save.bag for where that
  -- line is drawn); the PC's do not.
  local bagLayout = f.bag
  if type(save.inventory) == "table" and bagLayout then
    local order, why = Gen3Save.pocketOrder(cw)
    if not order then
      unwritable = unwritable or {}
      unwritable[#unwritable + 1] =
        { what = "bag", reason = tostring(why) }
    else
      -- THE PLAYER'S OWN ORDER FIRST.  `bagOrder` is the sequence the import
      -- read the bag in, and Emerald's bag is not sorted -- it is the order
      -- things were picked up, and the player has been re-arranging it since
      -- the first Potion.  Anything the order does not name (picked up in
      -- this port, so never in that list) follows, by item id, so that two
      -- exports of the same save produce the same bytes.
      local placed, sequence = {}, {}
      for _, id in ipairs(save.bagOrder or {}) do
        if not placed[id] and (save.inventory[id] or 0) > 0 then
          placed[id] = true
          sequence[#sequence + 1] = id
        end
      end
      local rest = {}
      for id, count in pairs(save.inventory) do
        if not placed[id] and (tonumber(count) or 0) > 0 then
          rest[#rest + 1] = id
        end
      end
      table.sort(rest, function(a, b)
        return (cw.itemsIndex[a] or 0) < (cw.itemsIndex[b] or 0)
      end)
      for _, id in ipairs(rest) do sequence[#sequence + 1] = id end

      local slots = {}
      for i = 1, #order do slots[i] = {} end
      local byName = {}
      for i, name in ipairs(order) do byName[name] = i end
      for _, id in ipairs(sequence) do
        local index = cw.itemsIndex[id]
        local def = cw.itemDefs[id]
        local pocket = def and def.pocket and byName[def.pocket]
        if index and pocket then
          local into = slots[pocket]
          if #into < bagLayout.capacities[pocket] then
            into[#into + 1] = { index = index,
                                count = math.floor(save.inventory[id]) }
          else
            -- A POCKET THAT IS FULL IS SAID OUT LOUD rather than spilled into
            -- the next array, which is a different pocket and would put
            -- berries among the TMs.
            unwritable = unwritable or {}
            unwritable[#unwritable + 1] =
              { what = "item", id = id,
                reason = ("the %s pocket holds %d and is full")
                         :format(def.pocket, bagLayout.capacities[pocket]) }
          end
        elseif index then
          unwritable = unwritable or {}
          unwritable[#unwritable + 1] =
            { what = "item", id = id,
              reason = "this item names no pocket, so there is no array for it" }
        end
      end
      for p, at in ipairs(bagLayout.pockets) do
        for slot = 0, bagLayout.capacities[p] - 1 do
          local o = at + slot * bagLayout.itemSlotSize
          local entry = slots[p] and slots[p][slot + 1]
          if entry then
            -- the count is clamped to the field, not to a stack size: this
            -- cartridge's own cap is not among the numbers the import derives,
            -- and inventing one would silently take items away
            local n = math.max(0, math.min(65535, entry.count))
            b1 = put(b1, o, b16(entry.index % 65536)
                            .. b16(xorU32(n, key) % 65536))
          else
            b1 = put(b1, o, b16(0) .. b16(xorU32(0, key) % 65536))
          end
        end
      end
    end
  end

  -- ...AND THE PC'S FIFTY SLOTS, whose quantities are stored plain
  if type(save.pcItems) == "table" and bagLayout and bagLayout.pcItems then
    local placed, sequence = {}, {}
    for _, id in ipairs(save.pcOrder or {}) do
      if not placed[id] and (save.pcItems[id] or 0) > 0 then
        placed[id] = true
        sequence[#sequence + 1] = id
      end
    end
    local rest = {}
    for id, count in pairs(save.pcItems) do
      if not placed[id] and (tonumber(count) or 0) > 0 then
        rest[#rest + 1] = id
      end
    end
    table.sort(rest, function(a, b)
      return (cw.itemsIndex[a] or 0) < (cw.itemsIndex[b] or 0)
    end)
    for _, id in ipairs(rest) do sequence[#sequence + 1] = id end
    for slot = 0, (bagLayout.pcItemCount or 0) - 1 do
      local o = bagLayout.pcItems + slot * bagLayout.itemSlotSize
      local id = sequence[slot + 1]
      local index = id and cw.itemsIndex[id]
      if index then
        local n = math.max(0, math.min(65535,
                                       math.floor(save.pcItems[id] or 0)))
        b1 = put(b1, o, b16(index % 65536) .. b16(n))
      else
        b1 = put(b1, o, b16(0) .. b16(0))
      end
    end
    for i = (bagLayout.pcItemCount or 0) + 1, #sequence do
      unwritable = unwritable or {}
      unwritable[#unwritable + 1] =
        { what = "item", id = sequence[i],
          reason = ("the PC holds %d items and is full")
                   :format(bagLayout.pcItemCount or 0) }
    end
  end

  return { slot = blocks.slot, counter = blocks.counter,
           block1 = b1, block2 = b2, storage = storage,
           unwritable = unwritable }
end

-- ---------------------------------------------------------------------------
-- A SAVE BUILT FROM NOTHING
--
-- Reported as: make export work "without having to import saves like the other
-- games do".  Gen 1 and Gen 2 write a save from an empty image; this refused
-- to, and the refusal was a real argument -- a Gen 3 save holds the Pokedex,
-- the Frontier records, the secret base, the mail and a hundred other things
-- this project does not model, and a save written from nothing is missing all
-- of them.  But "missing" and "wrong" are not the same thing, and the
-- difference is what makes this safe to do after all:
--
--   * WHAT THE PORT MODELS is written from the port, exactly as it is onto an
--     imported template.
--   * WHAT IT DOES NOT is ZERO -- which for every one of those systems is the
--     state a cartridge is in before the player has touched it.  An empty
--     Pokedex, no Frontier record, no secret base, no mail.  That is what a
--     playthrough which never saw a cartridge actually has.
--
-- The one field that is not simply zero-shaped is the ENCRYPTION KEY, and
-- zero is the right answer there too rather than a convenient one: every
-- encrypted field is stored value-XOR-key, so a key of zero stores the plain
-- value, and the cartridge re-rolls the key on its own schedule
-- (ApplyNewEncryptionKeyToAllEncryptedData walks every one of them when it
-- does).  A key this port invented would have to be written consistently into
-- six different places to mean anything, and means nothing if it is.
--
-- WRITTEN INTO SLOT 1 WITH COUNTER 1, matching FireRed's own
-- `gSaveCounter % NUM_SAVE_SLOTS` selection rule.  Counter 1 in slot 0 is
-- self-consistent enough for a naive decoder but real FireRed selects slot 1.
function Gen3Save.blank()
  local layout = Gen3Save.layout
  local f = need("a blank save")
  if not layout then error("Gen3Save: no sector layout (setLayout first)") end
  local storage = string.rep("\0", layout.pokemonStorageSize)
  -- ...EXCEPT THE BOX NAMES, which are not a system the player has yet to
  -- touch -- they are furniture the cartridge puts in before the first frame
  -- (ResetPokemonStorageSystem names every box), and a PC whose fourteen
  -- boxes are all called nothing is a broken screen rather than an empty one.
  -- The engine's own names are written over these by applyBlocks where it has
  -- them; this is what a box the port never named falls back to.
  local st = f.storage
  if st and st.boxNames and st.boxCount and st.boxNameLength then
    for b = 1, st.boxCount do
      local name = encodeText(("BOX %d"):format(b), st.boxNameLength)
      if name then
        storage = put(storage, st.boxNames + (b - 1) * st.boxNameLength, name)
      end
    end
  end
  local blocks = {
    block2 = string.rep("\0", layout.saveBlock2Size),
    block1 = string.rep("\0", layout.saveBlock1Size),
    storage = storage,
  }
  return Gen3Save.writeSlot(string.rep("\0", Gen3Save.SAVE_SIZE), 1, blocks, 1)
end

-- Lay the three structures back across fourteen sectors and sign each one.
-- The sector a chunk lands in is rotated by the counter exactly as the
-- cartridge rotates it, so a reader that assumes sector position equals sector
-- id is caught here rather than by a save that will not load.
function Gen3Save.writeSlot(image, slot, blocks, counter)
  local f = Gen3Save.layout
  local out = image
  for k = 0, Gen3Save.SECTORS_PER_SLOT - 1 do
    local id = (k + counter) % Gen3Save.SECTORS_PER_SLOT
    local row = f.sectors[id + 1]
    local src = (id == 0) and blocks.block2
                or (id <= 4 and blocks.block1 or blocks.storage)
    local data = src:sub(row.offset + 1, row.offset + row.size)
    local base = (slot * Gen3Save.SECTORS_PER_SLOT + k) * Gen3Save.SECTOR_SIZE
    local body = data .. string.rep("\0", Gen3Save.SECTOR_SIZE - 12 - #data)
    local sector = body .. b16(id) .. b16(0) .. b32(Gen3Save.SECURITY) .. b32(counter)
    local sum = Gen3Save.checksum(sector, 0, row.size)
    sector = body .. b16(id) .. b16(sum) .. b32(Gen3Save.SECURITY) .. b32(counter)
    out = put(out, base, sector)
  end
  return out
end

-- ---------------------------------------------------------------------------
-- The SaveConvert interface.
--
-- The container above is finished and proven: sectors, checksums, slot
-- rotation with its wraparound, structure reassembly, and the Pokemon crypto
-- including all 24 substructure orders.  What is NOT yet derived is where the
-- individual fields sit INSIDE SaveBlock1 and SaveBlock2 -- those offsets are
-- compiler-assigned, there is no table of them on the cartridge, and they have
-- to come out of the code that reads them the same way everything else here
-- did.
--
-- So this refuses, loudly, rather than decoding a Gen 3 save with offsets it
-- does not have.  That is the entire reason SaveConvert routes by generation
-- in the first place: before that split, a Gold save went through the Gen 1
-- codec and quietly lost every badge.  Returning "not yet" is the honest
-- version of that lesson; returning a half-populated save table is not.
-- Turn one decoded Pokemon into the shape the rest of this project uses.
-- The cartridge ids become this project's ids here and nowhere else, so a
-- species the cache does not know becomes a visible SPECIES_nnn placeholder
-- rather than a nil that surfaces three screens later as a blank sprite.
local function engineMon(mon, cw, isParty)
  if mon.empty then return nil end
  local ivs = Gen3Save.unpackIVs(mon.ivWord)
  local out = {
    species = cw.pokemonByIndex[mon.species]
              or ("SPECIES_%03d"):format(mon.species),
    personality = mon.personality,
    otId = mon.otId % 65536,
    secretId = math.floor(mon.otId / 65536) % 65536,
    exp = mon.experience,
    happiness = mon.friendship,
    ivs = { hp = ivs.hp, attack = ivs.attack, defense = ivs.defense,
            speed = ivs.speed, spatk = ivs.spAttack, spdef = ivs.spDefense },
    evs = { hp = mon.evs.hp, attack = mon.evs.attack,
            defense = mon.evs.defense, speed = mon.evs.speed,
            spatk = mon.evs.spAttack, spdef = mon.evs.spDefense },
    moves = {},
    isEgg = ivs.isEgg or nil,
    altAbility = ivs.altAbility or nil,
    -- shininess is DERIVED in Gen 3, never stored; a save editor that writes
    -- it as a flag is writing to a field that does not exist
    shiny = Gen3Save.isShiny(mon.personality, mon.otId) or nil,
    checksumOk = mon.checksumOk,
  }
  -- WHERE IT WAS MET, AND WHAT IT WAS CAUGHT IN.  Both live in Misc and
  -- neither survived the read before: the location was a byte off and the
  -- packed half-word was never touched at all.  The ball is what Emerald
  -- sends a Pokemon out in, so a save that drops it sends everything out in
  -- a POKe BALL.
  local origins = Gen3Save.unpackOrigins(mon.origins)
  if mon.metLocation and mon.metLocation ~= 0 then
    out.metLocation = mon.metLocation
  end
  if origins.metLevel and origins.metLevel > 0 then
    out.metLevel = origins.metLevel
  end
  -- ball 0 is "no ball recorded", which is what an egg and a starting
  -- Pokemon both carry; anything else names one of the twelve
  if origins.ball and origins.ball > 0 then
    out.ball = cw.itemsByIndex and cw.itemsByIndex[origins.ball] or origins.ball
  end
  if mon.heldItem and mon.heldItem ~= 0 then
    out.item = cw.itemsByIndex[mon.heldItem]
  end
  for i = 1, 4 do
    local id = mon.moves[i]
    if id and id ~= 0 then
      -- PP Ups are two bits per move inside one byte of the growth block
      local ups = math.floor((mon.ppBonuses or 0) / 4 ^ (i - 1)) % 4
      out.moves[#out.moves + 1] = { id = cw.movesByIndex[id]
                                    or ("MOVE_%03d"):format(id),
                                    pp = mon.pp[i], ppUps = ups }
    end
  end
  -- ...AND THE PLAIN HEADER.  None of these change how a Pokemon fights and
  -- all of them decide who it IS on the cartridge's own screens: what it is
  -- called, whose it is, and which language the two names are written in.
  -- They rode along for free while an export could only be written onto the
  -- record's own bytes; a save written from nothing has to carry them itself.
  local nick = decodeText(mon.nicknameBytes)
  if nick and nick ~= "" then out.nickname = nick end
  local ot = decodeText(mon.otNameBytes)
  if ot and ot ~= "" then out.gen3OtName = ot end
  if mon.language and mon.language ~= 0 then out.gen3Language = mon.language end
  if mon.markings and mon.markings ~= 0 then out.gen3Markings = mon.markings end
  if mon.pokerus and mon.pokerus ~= 0 then out.gen3Pokerus = mon.pokerus end
  if mon.contest then
    out.contest = { cool = mon.contest.cool, beauty = mon.contest.beauty,
                    cute = mon.contest.cute, smart = mon.contest.smart,
                    tough = mon.contest.tough, sheen = mon.contest.sheen }
  end
  if isParty then
    out.level = mon.level
    out.hp = mon.hp
    out.maxHp = mon.maxHp
    out.statusWord = mon.status
  end
  return out
end

function Gen3Save.decode(bytes, data)
  local blocks, err = Gen3Save.readBlocks(bytes)
  if not blocks then error(err or "neither save slot is intact") end
  local cw = Gen3Save.crosswalks(data)
  local f = need("the save")
  local warnings = {}
  local function warn(m) warnings[#warnings + 1] = m end

  local player = Gen3Save.readPlayer(blocks)
  local save = {
    meta = { format = "gen3_import", slot = blocks.slot },
    player = {
      name = decodeText(player.nameBytes),
      id = player.publicId,
      secretId = player.secretId,
      gender = (player.gender % 2 == 1) and "girl" or "boy",
    },
    money = player.money,
    coins = player.coins,
    berryPowder = player.berryPowder,
    gen3BattlePoints = player.battlePoints,
    gen3DewfordTrend = player.dewfordTrend,
    gen3Stats = player.gameStats,
    inventory = {},
    pcItems = {},
    flags = {},
    gen3Vars = {},
    party = {},
    boxes = {},
    pokedex = { seen = {}, owned = {} },
    currentBox = Gen3Save.currentBox(blocks.storage) or 1,
    -- this project keeps play time as a single float of SECONDS
    playTime = player.playTime.hours * 3600 + player.playTime.minutes * 60
               + player.playTime.seconds + player.playTime.vblanks / 60,
  }

  -- the bag, folded into one flat inventory the way the Gen 1 and Gen 2
  -- codecs do, with the pocket order kept so an export can rebuild it.
  -- THROUGH THE KEY: the five pockets store the quantity XORed with
  -- SaveBlock2+$AC (see Gen3Save.bag), and reading it without gave every
  -- imported item a count in the tens of thousands.
  local bagKey = Gen3Save.encryptionKey(blocks.block2)
  local order = {}
  for _, pocket in ipairs(Gen3Save.bag(blocks.block1, bagKey) or {}) do
    for _, slot in ipairs(pocket) do
      local id = cw.itemsByIndex[slot.item]
      if id then
        save.inventory[id] = (save.inventory[id] or 0) + slot.count
        order[#order + 1] = id
      else
        warn(("unknown item %d in the bag"):format(slot.item))
      end
    end
  end
  save.bagOrder = order
  local pcOrder = {}
  -- ...and the PC's quantities are stored PLAIN, which is why the same call
  -- reads them without the key applied to them (Gen3Save.bag leaves the pc
  -- list alone)
  for _, slot in ipairs((Gen3Save.bag(blocks.block1, bagKey) or {}).pc or {}) do
    local id = cw.itemsByIndex[slot.item]
    if id then
      save.pcItems[id] = (save.pcItems[id] or 0) + slot.count
      pcOrder[#pcOrder + 1] = id
    end
  end
  save.pcOrder = pcOrder

  for i, mon in ipairs(Gen3Save.party(blocks.block1) or {}) do
    save.party[i] = engineMon(mon, cw, true)
  end

  local st = f.storage
  for b = 1, (st and st.boxCount or 0) do
    local box = Gen3Save.box(blocks.storage, b)
    local out = { name = decodeText(box.nameBytes), wallpaper = box.wallpaper }
    for _, mon in ipairs(box) do
      out[mon.slot] = engineMon(mon, cw, false)
    end
    save.boxes[b] = out
  end

  -- Flags and variables land under the same names the script VM uses, because
  -- a save whose flags the scripts cannot read is not an imported save.
  for id = 1, f.flagBytes * 8 - 1 do
    if Gen3Save.flag(blocks.block1, id) then
      save.flags[("FLAG_G3_%04X"):format(id)] = true
    end
  end
  local base = f.varsStartId or 0x4000
  for i = 0, (f.varCount or 0) - 1 do
    local v = Gen3Save.var(blocks.block1, base + i)
    if v and v ~= 0 then save.gen3Vars[base + i] = v end
  end
  save.pokedex = readPokedex(blocks, cw)
  local pdx = (f.saveBlock2 or {}).pokedex
  if pdx and pdx.nationalMagic and pdx.nationalMagicValue
     and pdx.nationalFlagId and pdx.nationalVarId and pdx.nationalVarValue then
    local flagName = ("FLAG_G3_%04X"):format(pdx.nationalFlagId)
    save.nationalDex = u8(blocks.block2, pdx.nationalMagic)
        == pdx.nationalMagicValue
      and save.flags[flagName] == true
      and save.gen3Vars[pdx.nationalVarId] == pdx.nationalVarValue
  end

  -- ...AND WHAT IS GROWING IN HOENN'S EIGHTY-EIGHT PLOTS.  A cache from
  -- before the berry block was derived carries no offset for it; then this
  -- reads nothing and the save arrives exactly as it used to.
  local trees = Gen3Save.berryTrees(blocks.block1)
  if trees and next(trees) then save.gen3BerryTrees = trees end

  -- ...WHO LIVES IN THE HOUSE IN MAUVILLE, and what is in the decoration PC.
  -- Both come from the cartridge rather than being recomputed: the man was
  -- rolled once when that save was new, and the decorations are the player's.
  local man = Gen3Save.mauvilleMan(blocks.block1)
  if man then save.gen3MauvilleMan = man end
  local decorations = Gen3Save.decorations(blocks.block1)
  if decorations and next(decorations) then
    save.gen3 = save.gen3 or {}
    save.gen3.decorations = decorations
  end
  -- ...and which TRENDY SAYINGS that player has been given. Left absent when
  -- the save has none, so a fresh import is indistinguishable from what this
  -- port would have built itself.
  local trendy = Gen3Save.trendyPhrases(blocks.block1)
  if trendy then save.gen3TrendyPhrases = trendy end

  -- The saved location.  Which of the two bytes after the coordinates is the
  -- map GROUP and which is the map NUMBER was never derived, so it is not
  -- assumed: the pair has to name one of the maps the extractor found, and if
  -- it does not, the spawn is left alone and the reason is said out loud.
  local at = f.saveBlock1.location
  if at and cw.mapsHaveGroups then
    local group, number = u8(blocks.block1, at), u8(blocks.block1, at + 1)
    local mapId = cw.mapsByGroupNumber[group * 256 + number]
    if mapId then
      save.player.map = mapId
      save.player.x = u16(blocks.block1, f.saveBlock1.posX)
      save.player.y = u16(blocks.block1, f.saveBlock1.posY)
    else
      warn(("no map is group %d number %d, so the spawn is left at the default")
           :format(group, number))
    end
  end

  save.warnings = warnings
  save.rawImport = bytes
  return save
end

-- encode: a save table back onto the image it came from.
--
-- A template is REQUIRED and this refuses without one, which is the same call
-- Gen 1 and Gen 2 make for the same reason: a Gen 3 save holds hundreds of
-- fields, this project models a few dozen, and a save written from nothing
-- would be missing the Pokedex, the Frontier records, the secret base and the
-- mail -- and would look fine until the cartridge loaded it.
function Gen3Save.encode(save, data, template)
  local image = template or (save and save.rawImport)
  -- A PLAYTHROUGH THAT NEVER CAME OFF A CARTRIDGE gets a blank one built for
  -- it (see Gen3Save.blank).  This used to refuse, and the argument for
  -- refusing was real -- everything this project does not model would be
  -- missing -- but "missing" is the same thing as "not yet touched" for every
  -- one of those systems, which is exactly true of a save that started here.
  -- What is NOT allowed is the middle case: an image of the wrong size is a
  -- file that is not a Gen 3 save, and quietly replacing it with a blank one
  -- would throw away whatever the caller actually meant to write onto.
  if image == nil then
    image = Gen3Save.blank()
  elseif type(image) ~= "string" or #image ~= Gen3Save.SAVE_SIZE then
    error(("a Gen 3 save image is %d bytes; this one is %s")
          :format(Gen3Save.SAVE_SIZE,
                  type(image) == "string" and (#image .. " bytes")
                                          or type(image)))
  end
  local blocks, err = Gen3Save.readBlocks(image)
  if not blocks then error(err or "the template save is not intact") end

  local patched = Gen3Save.applyBlocks(blocks, save, Gen3Save.crosswalks(data))
  -- into the OTHER slot, with the next counter: the slot just read stays
  -- intact as the backup, which is the whole point of there being two
  local target = 1 - blocks.slot
  local counter = (blocks.counter + 1) % 4294967296
  -- ...and a SECOND return: the Pokemon the box writer could not carry, so a
  -- caller can say so rather than the player finding out from the cartridge.
  -- See applyBlocks -- these are the ones caught in the port, which have no
  -- cartridge record to relocate.
  return Gen3Save.writeSlot(image, target, patched, counter), patched.unwritable
end

return Gen3Save
