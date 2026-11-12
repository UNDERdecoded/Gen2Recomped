-- THE ONLINE LOOK IN BATTLE.
--
--   * YOUR BACK PIC wears your MY LOOK colours in every battle -- offline
--     single-player ones too (one look everywhere, OPTIONS -> MY LOOK), link
--     battles, worlds and rooms.  A save with no look keeps the cartridge's
--     back pic untouched.  Back pics
--     exist only for the protagonists, so a chosen trainer sheet gets the
--     protagonist of the player's gender; a chosen protagonist of the other
--     gender brings that one's back pic.  The DS throw strip and the Gen 3
--     throw strip are painted the same way.
--   * THE LINK OPPONENT'S FRONT PIC (Gen 3+): the cartridges show the other
--     player's own trainer front in a link battle intro (Gen 3's Brendan/May,
--     the DS trainer classes 0 / 1).  This shows it, in the peer's colours,
--     and slides it off before "X sent out Y!".  A peer who chose another
--     trainer sheet gets that class's front where the cache names classes
--     (Gen 4), else the protagonist of their gender.  Gen 1 / 2 Colosseums
--     never showed one, and still do not.
--   * `active` is emptied at the start of every battle and only filled for
--     the cases above (catching demos and the like are never touched).
--
-- Hooks (anchored, src/battle/BattleState.lua): BattleLook.begin + backPath
-- before the back pic loads; BattleLook.forPath inside getImage (the paint
-- joins the cache key and recolours the ImageData); BattleLook.linkFront in
-- enter(); BattleLook.image for the DS throw sheet (src/battle/Gen4Battle.lua).
-- The peer's look arrives in the link hello (Handshake.hello `look`).

local Avatar = require("src.online.world.Avatar")

local BattleLook = {}

BattleLook.active = {}   -- path -> paint, for the battle being built

function BattleLook.reset() BattleLook.active = {} BattleLook.battle = nil end

-- a new battle starts with nothing registered; the same battle keeps what
-- an earlier hook of its own enter() put there (linkFront runs first)
local function own(battle)
  if BattleLook.battle ~= battle then
    BattleLook.active = {}
    BattleLook.battle = battle
  end
end

local function forms(data)
  local f = data and data.field and data.field.playerForms
  return type(f) == "table" and f or nil
end

local function gen(game)
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and tonumber(GV.generation and GV.generation()) or 0
end

-- is the player's own look worn in this battle?  Every battle now (one look
-- offline and online); begin() still finds nothing when no look is saved
function BattleLook.ownApplies(battle)
  if not battle then return false end
  return true
end

function BattleLook.begin(battle)
  own(battle)
  battle.ownLook = nil
  if not BattleLook.ownApplies(battle) then return end
  local saved = Avatar.saved(battle.game)
  if not saved then return end
  battle.ownLook = { r = saved.r, paint = Avatar.paint({ t = saved.t, c = saved.c }) }
end

local function register(data, path, paint)
  if type(path) ~= "string" or not paint then return end
  BattleLook.active[path] = paint
  local ts = data and data.gen4_trainer_sprites
  local throws = type(ts) == "table" and type(ts.backThrows) == "table" and ts.backThrows or {}
  local rec = throws[path]
  if type(rec) == "table" and type(rec.path) == "string" then BattleLook.active[rec.path] = paint end
end

-- the back pic path to use (the chosen protagonist's), registered for paint
function BattleLook.backPath(battle, backPath, trueColor)
  local own = battle and battle.ownLook
  if not own or battle.demo or battle.oakDemo or battle.pokedudeDemo or battle.demoBackPath then
    return backPath, trueColor
  end
  local data = battle.data or (battle.game and battle.game.data)
  local fs = forms(data)
  local g = (own.r == "boy" or own.r == "girl") and own.r or nil
  if g and fs and type(fs[g]) == "table" and type(fs[g].back) == "string" then
    if fs[g].back ~= backPath then backPath = fs[g].back trueColor = true end
    if type(fs[g].backStrip) == "string" then register(data, fs[g].backStrip, own.paint) end
  else
    -- the save's own form: its strip too
    for _, f in pairs(fs or {}) do
      if type(f) == "table" and f.back == backPath and type(f.backStrip) == "string" then
        register(data, f.backStrip, own.paint)
      end
    end
  end
  register(data, backPath, own.paint)
  return backPath, trueColor
end

-- THE BACK PIC AT REST, as the battle shows it before the throw: on the DS
-- the battle draws frame 1 of the throw strip (Gen4Battle.dsBackFrame), not
-- the still -- and Black / White's still is the ROM's cell 0 alone, the body
-- WITHOUT ITS ARMS (they are separate cells of the throw).  Anything that
-- previews the back (MY LOOK) asks here so it shows what a battle shows.
-- -> image, quad (nil = the whole image), width, height; nil when none
function BattleLook.restBack(data, backPath, paint)
  if type(backPath) ~= "string" then return nil end
  local ts = data and data.gen4_trainer_sprites
  local throws = type(ts) == "table" and type(ts.backThrows) == "table" and ts.backThrows or nil
  local rec = throws and throws[backPath]
  if not (type(rec) == "table" and type(rec.path) == "string"
          and tonumber(rec.width) and tonumber(rec.height)) then
    rec = nil
  end
  local path = rec and rec.path or backPath
  local img = paint and Avatar.paintedPathImage(path, paint, data) or nil
  if not img then
    local ok, im = pcall(require("src.render.Assets").image, path)
    img = ok and im or nil
  end
  if not img and rec then
    -- no strip on disk: the still after all
    rec, path = nil, backPath
    img = paint and Avatar.paintedPathImage(path, paint, data) or require("src.render.Assets").image(path)
  end
  if not img then return nil end
  local iw, ih = img:getDimensions()
  if rec and rec.width <= iw and rec.height <= ih then
    return img, love.graphics.newQuad(0, 0, rec.width, rec.height, iw, ih), rec.width, rec.height
  end
  return img, nil, iw, ih
end

function BattleLook.forPath(path)
  return path and BattleLook.active[path] or nil
end

-- a recoloured ImageData for a registered path (getImage's load)
function BattleLook.imageData(path, data)
  local paint = BattleLook.forPath(path)
  if not paint then return nil end
  -- (the Game module's data when the caller has no global Game)
  if not data then
    local G = package.loaded["src.core.Game"]
    data = G and G.data
  end
  local hand = Avatar.handFor(data, path)
  return Avatar.pathImageData(path, paint, hand, false)
end

-- Assets.image, painted when the path is registered (the DS throw sheet)
function BattleLook.image(path)
  local paint = BattleLook.forPath(path)
  if paint then
    local G = package.loaded["src.core.Game"]
    local img = Avatar.paintedPathImage(path, paint, G and G.data)
    if img then return img end
  end
  return require("src.render.Assets").image(path)
end

-- the front pic a peer's look stands for in THIS cache
function BattleLook.frontPathFor(data, look, game)
  if type(look) ~= "table" then return nil end
  local av = type(look.av) == "table" and look.av or {}
  local g = (av.r == "boy" or av.r == "girl") and av.r or (look.gender == "girl" and "girl") or "boy"
  local ts = data and data.gen4_trainer_sprites
  local classes = type(ts) == "table" and type(ts.classes) == "table" and ts.classes or nil
  -- a chosen trainer class, by name, in a cache that names its classes
  if av.r == "npc" and av.g == (game or Avatar.gameId()) and classes and av.s
     and data.sprites and data.sprites[av.s] then
    local want = Avatar.sheetLabel(data.sprites[av.s], av.s):gsub("%s", "")
    for _, c in pairs(classes) do
      if type(c) == "table" and type(c.name) == "string" and type(c.path) == "string"
         and c.name:upper():gsub("%s", "") == want then
        return c.path, g
      end
    end
  end
  local fs = forms(data)
  local f = fs and (fs[g] or fs.boy)
  if type(f) == "table" and type(f.intro) == "string" then return f.intro, g end
  if classes then
    local c = classes[g == "girl" and 1 or 0]
    if type(c) == "table" and type(c.path) == "string" then return c.path, g end
  end
  -- BLACK / WHITE: Hilbert and Hilda are trfgra pictures 0 and 1, which the
  -- import already writes (Gen5TrainerPics `pictures`) -- no trainer row
  -- uses classes 0 / 1, so `classes` never named them
  local pics = type(ts) == "table" and type(ts.pictures) == "table" and ts.pictures or nil
  if pics then
    local c = pics[g == "girl" and 1 or 0]
    if type(c) == "table" and type(c.path) == "string" then return c.path, g end
  end
  if type(f) == "table" and type(f.card) == "string" then return f.card, g end
  return nil
end

-- one front pic for one look, painted; the paint is set just for this load
-- (two opponents may share a path in different colours: each load gets its
-- own cache key from the paint)
local function frontPic(data, look, getImage)
  local path = BattleLook.frontPathFor(data, look)
  if not path then return nil end
  local paint = Avatar.tintOf(look)
  BattleLook.active[path] = paint
  local img = getImage(path, nil, true)
  return img
end

-- a multi battle: both opponents, each in their own look; a computer seat
-- (the Subway's trainers) shows none, as before
function BattleLook.multiFronts(battle, getImage)
  local data = battle.data or (battle.game and battle.game.data)
  local seats = battle.multiFoeSeats or {}
  local pics = {}
  for i = 1, 2 do
    local seat = seats[i]
    if seat ~= nil and not (battle.multiAi and battle.multiAi[seat]) then
      pics[i] = frontPic(data, (battle.multiLooks or {})[seat] or {}, getImage)
    end
  end
  local a, b = pics[1], pics[2]
  if not a then a, b = b, nil end
  if not a then return false end
  battle.trainerPic = a
  battle.trainerPicB = b
  battle.linkFrontPic = true
  return true
end

-- the link opponent's front pic (Gen 3+); getImage is BattleState's loader
function BattleLook.linkFront(battle, getImage)
  if not battle or battle.kind ~= "link" or battle.trainerPic then return false end
  own(battle)
  if gen(battle.game) < 3 then return false end
  if battle.linkMulti then return BattleLook.multiFronts(battle, getImage) end
  local data = battle.data or (battle.game and battle.game.data)
  local look = battle.peerLook or {}
  local path = BattleLook.frontPathFor(data, look)
  if not path then return false end
  local paint = Avatar.tintOf(look)
  if paint then BattleLook.active[path] = paint end
  local img = getImage(path, nil, true)
  if not img then return false end
  battle.trainerPic = img
  battle.linkFrontPic = true
  return true
end

return BattleLook
