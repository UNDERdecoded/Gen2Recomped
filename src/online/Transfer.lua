-- One-way upward transfer between two players (docs/online-design.md,
-- "Decisions": cross-generation online, one way upward).
--
-- The cartridges' own same-owner moves, played across a link:
--
--   Gen 3 -> Gen 4   PAL PARK      (src/world/Gen4PalPark.lua)
--   Gen 4 -> Gen 5   POKé TRANSFER (src/world/Gen5PokeTransfer.lua)
--
-- The rules and the conversion are THOSE MODULES', not new ones:
--   * the refusal is Gen4PalPark.refusal (no EGG, none of the Game Pak's
--     eight HM moves) or Gen5PokeTransfer.refusal (no EGG, no held item,
--     none of Gen IV's HM moves);
--   * the rebuild is Gen4PalPark.fromGen3 / CrossGen.convert, with the
--     receiver's records: dex number for the species, the move by its
--     cartridge number and name, items and the ball by name, then
--     Pokemon.applySeed off the personality and IVs.
-- Both offline modules read the SOURCE game's records off its cache on the
-- same install.  Online the source is another machine, so the packet
-- (MonCodec.pack) carries what they read from it -- the national dex
-- number, each move's number and name, the item's and ball's names -- and
-- a stand-in `src` is built from it.
--
-- The receiver is always the newer game, and it is a gift, not a swap:
-- TransferSession below moves one mon from the sender to the receiver and
-- nothing back.  The offline rules that do not fit one live gift -- six at
-- a time, Pal Park's once a day per Game Pak, the catching minigames -- are
-- not applied; the per-mon legality is.

local MonCodec = require("src.online.MonCodec")
local CompatRules = require("src.online.CompatRules")

local Transfer = {}

-- the source game's version id for the offline converters' `version`
-- argument (Pal Park stamps it as gen3Origin)
local function versionOf(hello, fallback)
  return (type(hello) == "table" and type(hello.game) == "string" and hello.game) or fallback
end

-- the stand-in for the source game's records, rebuilt from the packet
function Transfer.sourceFromPacked(packed)
  local src = { pokemon = {}, moves = {}, items = {} }
  if packed.species ~= nil then
    src.pokemon[packed.species] = { dex = packed.dex, index = packed.dex }
  end
  for _, mv in ipairs(packed.moves or {}) do
    if mv.id ~= nil then
      src.moves[mv.id] = { index = tonumber(mv.index), name = mv.name }
    end
  end
  local held = packed.item or packed.heldItem
  if held ~= nil and packed.itemName then src.items[held] = { name = packed.itemName } end
  if packed.ball ~= nil and packed.ballName then src.items[packed.ball] = { name = packed.ballName } end
  return src
end

-- the "raw" Game Pak / DS record the offline converters take
function Transfer.rawFromPacked(packed)
  local raw = {}
  for k, v in pairs(packed) do raw[k] = v end
  raw.item = packed.item or packed.heldItem
  raw.moves = {}
  for i, mv in ipairs(packed.moves or {}) do
    raw.moves[i] = { id = mv.id, pp = mv.pp, ppUps = mv.ppUps }
  end
  return raw
end

-- why this packed mon may not make the move, or nil (the offline module's
-- own answer: "egg", "hm", "item")
function Transfer.refusal(packed, route)
  if type(packed) ~= "table" then return "nothing" end
  local src, raw = Transfer.sourceFromPacked(packed), Transfer.rawFromPacked(packed)
  if route == "palpark" then
    return require("src.world.Gen4PalPark").refusal(src, raw)
  elseif route == "poketransfer" then
    return require("src.world.Gen5PokeTransfer").refusal(src, raw)
  end
  return "no route"
end

Transfer.REFUSAL_TEXT = {
  egg = "an EGG can't move",
  hm = "knows an HM move",
  item = "holding an item",
  nothing = "nothing there",
}

-- WalkerLink.dexOf reads the SOURCE game's cache; the packet already names
-- the dex number, so it answers from that for the length of one conversion
local function withDex(dex, fn)
  local Link = require("src.pokewalker.WalkerLink")
  local saved = Link.dexOf
  Link.dexOf = function() return dex end
  local ok, a, b = pcall(fn)
  Link.dexOf = saved
  if not ok then return nil, tostring(a) end
  return a, b
end

-- packed (sender's generation) -> a mon in the receiver's shape, or nil, why.
-- data: the receiver's records; route: "palpark" | "poketransfer";
-- fromVersion: the sender's game id.
function Transfer.convert(data, packed, route, fromVersion)
  if type(packed) ~= "table" or not tonumber(packed.wire) then return nil, "not a POKéMON" end
  local fromGen = route == "palpark" and 3 or 4
  if packed.gen ~= fromGen or MonCodec.genOf(data) ~= fromGen + 1 then
    return nil, "not this transfer's games"
  end
  local why = Transfer.refusal(packed, route)
  if why then return nil, Transfer.REFUSAL_TEXT[why] or why end
  local dex = tonumber(packed.dex)
  if not dex or not (data.pokemon and data.pokemon[dex]) then return nil, "not in this game" end
  -- the sender's own data must pass the sender generation's checks first:
  -- a tampered packet is refused before anything is built from it.  The
  -- check runs against a view of the receiver's records in the sender's
  -- generation's ids, which the converters then translate.
  local src, raw = Transfer.sourceFromPacked(packed), Transfer.rawFromPacked(packed)
  local game = { data = data }
  local mon, err = withDex(dex, function()
    if route == "palpark" then
      return require("src.world.Gen4PalPark").fromGen3(game, fromVersion or "emerald", src, raw)
    end
    return require("src.pokemon.CrossGen").convert(game, fromVersion or "platinum", src, raw)
  end)
  if not mon then return nil, err or "can't convert" end
  -- (Poke Transfer's nature and ability slot: CrossGen.convert keeps the
  -- Gen IV ones on Black / White itself, CG.natureFor)
  -- what the receiver files must pass the receiver's own checks
  local packedHere = MonCodec.pack(data, mon)
  local final, why2 = MonCodec.unpack(data, packedHere, { strict = true })
  if not final then return nil, why2 end
  return final
end

-- ------------------------------------------------------------ session
--
-- A one-way gift, symmetric in messages:
--
--   sender                         receiver
--   opening(): {offer, mons}  -->  handle(offer): the sender's eligible mons
--   pick(i):   {gift, index}  -->  handle(gift): converts; stage "confirming"
--                             <--  accept(ok): {accept, ok}
--   handle(accept):                (waits)
--     stage "done", apply()
--     removes the mon         -->  {commit}
--                                  handle(commit): stage "done", apply()
--                                  files the mon
--
-- The sender gives the mon up before the receiver files it, so a lost
-- `commit` loses the mon rather than cloning it (the GTS escrow rule).

local TransferSession = {}
TransferSession.__index = TransferSession
Transfer.TransferSession = TransferSession

-- opts: { myHello, peerHello, route, direction = "send"|"receive", peerName }
function TransferSession.new(data, party, opts)
  opts = opts or {}
  local pair = opts.pair
  if not pair and opts.myHello and opts.peerHello then
    pair = CompatRules.pair(opts.myHello, opts.peerHello)
  end
  local t = pair and pair.transfer
  local self = setmetatable({
    data = data, party = party, peerName = opts.peerName,
    myHello = opts.myHello, peerHello = opts.peerHello,
    route = t and t.route, direction = t and t.direction,
    eligible = {}, reasons = {}, sendIndices = {},
    offer = nil, gift = nil, giftIndex = nil,
  }, TransferSession)
  if not t then
    self.stage, self.error = "cancelled", "these games have no transfer"
    return self
  end
  if self.direction == "send" then
    for i, mon in ipairs(party or {}) do
      local packed = MonCodec.pack(data, mon)
      local why = Transfer.refusal(packed, self.route)
      self.eligible[i] = why == nil
      self.reasons[i] = why and (Transfer.REFUSAL_TEXT[why] or why) or nil
      if not why then self.sendIndices[#self.sendIndices + 1] = i end
    end
    self.stage = "picking"
  else
    self.stage = "waitOffer"
  end
  return self
end

function TransferSession:canPick(index)
  return self.direction == "send" and self.eligible[index] == true
end

function TransferSession:opening()
  if self.direction ~= "send" then return nil end
  local mons = {}
  for _, i in ipairs(self.sendIndices) do mons[#mons + 1] = MonCodec.pack(self.data, self.party[i]) end
  return { type = "offer", mons = mons }
end

function TransferSession:pick(index)
  if self.stage ~= "picking" or not self:canPick(index) then return nil end
  local pos
  for p, i in ipairs(self.sendIndices) do if i == index then pos = p end end
  self.giftIndex = index
  self.stage = "waitAccept"
  return { type = "gift", index = pos }
end

function TransferSession:accept(ok)
  if self.direction ~= "receive" or self.stage ~= "confirming" then return nil end
  if not ok then self.stage = "cancelled" end
  if ok then self.stage = "waitCommit" end
  return { type = "accept", ok = ok and true or false }
end

-- returns a message to put on the wire, or nil
function TransferSession:handle(msg)
  if type(msg) ~= "table" then return nil end
  if msg.type == "bye" then self.stage = "cancelled" return nil end
  if self.direction == "receive" then
    if msg.type == "offer" and self.stage == "waitOffer" then
      self.offer = type(msg.mons) == "table" and msg.mons or {}
      self.stage = "waitGift"
    elseif msg.type == "gift" and self.stage == "waitGift" then
      local packed = self.offer and self.offer[tonumber(msg.index) or -1]
      local mon, why = Transfer.convert(self.data, packed, self.route,
                                        versionOf(self.peerHello))
      if not mon then
        self.stage, self.error = "cancelled", why
        return { type = "accept", ok = false, why = why }
      end
      self.gift = mon
      self.stage = "confirming"
    elseif msg.type == "commit" and self.stage == "waitCommit" then
      self.stage = "done"
    end
  else
    if msg.type == "accept" and self.stage == "waitAccept" then
      if msg.ok then
        self.stage = "done"
        return { type = "commit" }
      end
      self.stage, self.error = "cancelled", type(msg.why) == "string" and msg.why:sub(1, 40) or nil
    end
  end
  return nil
end

-- the sender: the mon leaves the party.  The receiver: the mon is filed
-- (the party when there is room, else the PC, as Pal Park and the lab do)
-- and the Pokédex marks it.  Returns the mon that moved.
function TransferSession:apply(game)
  assert(self.stage == "done", "transfer not complete")
  if self.direction == "send" then
    local sent = table.remove(self.party, self.giftIndex)
    return sent
  end
  local mon = self.gift
  mon.traded = true
  local save = game and game.save
  if save then
    if #(save.party or {}) < 6 then
      save.party = save.party or {}
      table.insert(save.party, mon)
    else
      pcall(require("src.pokemon.Boxes").deposit, save, mon)
    end
    if save.pokedex then
      save.pokedex.seen = save.pokedex.seen or {}
      save.pokedex.owned = save.pokedex.owned or {}
      save.pokedex.seen[mon.species] = true
      save.pokedex.owned[mon.species] = true
    end
  end
  pcall(function()
    require("src.mods.Runtime").emit("pokemon.received",
      { mon = mon, from = "transfer", peerName = self.peerName })
  end)
  return mon
end

return Transfer
