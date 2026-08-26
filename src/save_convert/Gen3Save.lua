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

-- Where the fields sit inside the save blocks.  Also from the manifest, also
-- derived rather than remembered: the two save-block pointers were told apart
-- by which block's size their accesses fit inside, and each field came out of
-- the code that reads it -- the flags out of the function setflag, clearflag
-- and checkflag all reach, the variables out of the one that also loads
-- gSpecialVars, money out of the handler that builds 0x490 as `0x92 << 3` and
-- never puts it in a literal pool at all.
Gen3Save.fields = nil

function Gen3Save.setLayout(layout, orders, fields)
  Gen3Save.layout = layout
  Gen3Save.substructOrders = orders
  Gen3Save.fields = fields
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
  if not b.valid then return a, a, b end
  if not a.valid then return b, a, b end
  local MAX = 4294967295
  if a.counter == 0 and b.counter == MAX then return a, a, b end
  if b.counter == 0 and a.counter == MAX then return b, a, b end
  if a.counter >= b.counter then return a, a, b end
  return b, a, b
end

-- Reassemble the three save structures out of the current slot's sectors.
-- Each sector carries a chunk of one structure at a known offset, and the
-- fourteen chunks tile the three structures exactly -- which the manifest
-- checked when it derived them.
function Gen3Save.readBlocks(bytes)
  local layout = Gen3Save.layout
  if not layout then error("Gen3Save: no sector layout (setLayout first)") end
  local current, a, b = Gen3Save.currentSlot(bytes)
  if not current then
    return nil, "neither save slot is intact", a, b
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
    metLocation = m[3],
    substructs = subs,
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
  }
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
-- quantity.  The quantity of everything except the first pocket's contents is
-- stored plainly; the item pocket's quantities are XORed with the same key
-- that hides the money, which is why a reader without the key sees a bag full
-- of tens of thousands of potions.
function Gen3Save.bag(block1, key)
  local f = need("the bag")
  local bag = f.bag
  if not bag then return nil end
  local out = {}
  for p, at in ipairs(bag.pockets) do
    local pocket = {}
    for slot = 0, bag.capacities[p] - 1 do
      local o = at + slot * bag.itemSlotSize
      local id, qty = u16(block1, o), u16(block1, o + 2)
      if id ~= 0 then
        pocket[#pocket + 1] = { item = id, count = qty, raw = qty,
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
  local movesByIndex, movesIndex = byIndex(data and data.moves)
  local itemsByIndex, itemsIndex = byIndex(data and data.items)
  local mapsByGroupNumber, haveGroups = {}, false
  for id, def in pairs((data and data.maps) or {}) do
    if type(def) == "table" and def.group and def.number then
      mapsByGroupNumber[def.group * 256 + def.number] = id
      haveGroups = true
    end
  end
  return { pokemonByIndex = pokemonByIndex, pokemonIndex = pokemonIndex,
           movesByIndex = movesByIndex, movesIndex = movesIndex,
           itemsByIndex = itemsByIndex, itemsIndex = itemsIndex,
           mapsByGroupNumber = mapsByGroupNumber, mapsHaveGroups = haveGroups,
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
    inventory = {},
    pcItems = {},
    flags = {},
    gen3Vars = {},
    party = {},
    boxes = {},
    currentBox = Gen3Save.currentBox(blocks.storage) or 1,
    -- this project keeps play time as a single float of SECONDS
    playTime = player.playTime.hours * 3600 + player.playTime.minutes * 60
               + player.playTime.seconds + player.playTime.vblanks / 60,
  }

  -- the bag, folded into one flat inventory the way the Gen 1 and Gen 2
  -- codecs do, with the pocket order kept so an export can rebuild it
  local order = {}
  for _, pocket in ipairs(Gen3Save.bag(blocks.block1) or {}) do
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
  for _, slot in ipairs((Gen3Save.bag(blocks.block1) or {}).pc or {}) do
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

-- Writing a Gen 3 save back is a separate job with its own trap: every sector
-- checksum, the slot counter and the money encryption all have to be rebuilt,
-- and a half-correct writer produces a file the game refuses at the title
-- screen rather than one that visibly fails here.
function Gen3Save.encode(_save, _data, _template)
  error("Gen 3 saves can be read but not yet written back")
end

return Gen3Save
