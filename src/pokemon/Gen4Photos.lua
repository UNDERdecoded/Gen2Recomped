-- THE DRESS-UP AND CONTEST PHOTOS (Platinum's ImageClips, HGSS's
-- SaveFashionData -- the same save block in both, pt_photo round).
--
-- READ FROM CODE (pokeplatinum include/struct_defs/image_clips.h,
-- dress_up_photo.h, photo_pokemon.h, photo_accessory.h, src/unk_020298BC.c;
-- pokeheartgold include/fashion_case.h, asm/unk_0202B614.s):
--   * 11 dress-up photos (SAVED_PHOTOS_COUNT). Slot 0 is the player's own,
--     written by the dress-up app (ov22_02256F38 / HGSS ov41_022479A8);
--     slots 1..10 are other players' photos mixed in by record mixing
--     (sub_0202A6A8), which does not exist offline -- they stay empty here.
--   * 5 contest photos, one per contest type (unk_4C8[5]), written for the
--     winner at a contest's end (contest.c sub_0202A390).
--   * a photo is { integrity (EMPTY / FULL magic), PhotoPokemon (species,
--     nickname, personality, OT id, form, x, y, priority, trainer name and
--     gender), the title (an easy-chat sentence, only word 0 used), up to 10
--     PhotoAccessory (id, x, y, priority), the backdrop, the language }.
--     A slot always exists; "has data" is the FULL magic, and
--     DressUpPhoto_SetTitle writes even into an empty slot.
--
-- THE PORT'S FORM (save.gen4Photos, version-neutral):
--   { dressUp = { [0..10] = photo }, contest = { [0..4] = photo } }
--   photo = { full = true|false, title = word|nil, mon = { species, form,
--             personality, otId, shiny, nickname, gender }, monX, monY,
--             monZ, accessories = { { id, x, y, z }, ... }, backdrop, trainerName,
--             trainerGender (0 boy / 1 girl), language, rank, contestType }
--   z / monZ are the sprite priorities (ov22_02257B10; higher in front),
--   absent in photos from before they were kept (drawn Pokemon first).
--   Positions are STAGE-RELATIVE (INFERRED representation): the stage is
--   the 112 x 129 picture at (136, 16) in the dressing room
--   (ov22_02257BE8's hit box, READ); monX / monY is the Pokemon's centre,
--   an accessory's x / y its top-left. The cartridge keeps screen positions
--   of the confirm view instead (stage at 72, 56 -- ov22_02256C70 slides
--   everything by -64, +40); both describe the same picture.

local M = {}

M.DRESS_SLOTS, M.CONTEST_SLOTS = 11, 5
M.PHOTO_ACCESSORIES = 10          -- PHOTO_ACCESSORY_COUNT
M.CONTEST_ACCESSORIES = 20        -- UnkStruct_02029C88's 21 - 1
M.STAGE_W, M.STAGE_H = 112, 129
M.LANGUAGE_EN = 2                 -- gGameLanguage on a US cartridge

local function store(save)
  if not save then return nil end
  save.gen4Photos = save.gen4Photos or {}
  local s = save.gen4Photos
  s.dressUp = s.dressUp or {}
  s.contest = s.contest or {}
  -- a save from before the photo store: HGSS's ScrCmd_256 kept only the
  -- title, in `hgssPortrait`; it becomes photo 0's title (an empty photo,
  -- as the cartridge's would be) and the old field goes
  if type(save.hgssPortrait) == "table" then
    if save.hgssPortrait.title and not (s.dressUp[0] and s.dressUp[0].title) then
      s.dressUp[0] = s.dressUp[0] or { full = false }
      s.dressUp[0].title = tonumber(save.hgssPortrait.title)
    end
    save.hgssPortrait = nil
  end
  return s
end
M.store = store

local function list(save, kind)
  local s = store(save)
  if not s then return nil end
  return kind == "contest" and s.contest or s.dressUp
end

function M.slotCount(kind) return kind == "contest" and M.CONTEST_SLOTS or M.DRESS_SLOTS end

-- the slot's photo, or nil (out of range / never written)
function M.get(save, kind, slot)
  slot = math.floor(tonumber(slot) or -1)
  if slot < 0 or slot >= M.slotCount(kind) then return nil end
  local l = list(save, kind)
  return l and l[slot]
end

-- ImageClips_DressUpPhotoHasData / sub_02029D2C: the FULL magic
function M.hasData(save, kind, slot)
  local p = M.get(save, kind, slot)
  return p ~= nil and p.full == true
end

function M.countDressUp(save)
  local n = 0
  for i = 0, M.DRESS_SLOTS - 1 do if M.hasData(save, "dressUp", i) then n = n + 1 end end
  return n
end

local function speciesId(v)
  return tonumber(v) or tonumber(tostring(v or ""):match("(%d+)%s*$")) or 0
end
M.speciesId = speciesId

-- PhotoPokemon_SetDataFromMon: what of the Pokemon the photo keeps
function M.monCopy(mon)
  mon = mon or {}
  return { species = mon.species, form = mon.form, personality = mon.personality, otId = mon.otId,
           shiny = mon.shiny, nickname = mon.nickname, gender = mon.gender }
end

-- ov22_02256F38: DressUpPhoto_Init (the old photo and its title go), the
-- Pokemon, the trainer, the accessories on the stage, the backdrop, then
-- the language and the FULL magic
function M.writeDressUp(save, slot, args)
  local l = list(save, "dressUp")
  if not l then return nil end
  local acc = {}
  for i, a in ipairs(args.accessories or {}) do
    if i > M.PHOTO_ACCESSORIES then break end
    acc[i] = { id = a.id, x = a.x, y = a.y, z = a.z }
  end
  local p = { full = true, title = nil, mon = M.monCopy(args.mon), monX = args.monX, monY = args.monY, monZ = args.monZ,
              accessories = acc, backdrop = args.backdrop or 0,
              trainerName = args.trainerName, trainerGender = args.trainerGender or 0,
              language = M.LANGUAGE_EN }
  l[math.floor(tonumber(slot) or 0)] = p
  return p
end

-- contest.c: the winner's photo for its contest type (sub_0202A25C clears,
-- sub_0202A390 copies, sub_0202A240 sets the magic)
function M.writeContest(save, contestType, args)
  local l = list(save, "contest")
  local t = math.floor(tonumber(contestType) or -1)
  if not l or t < 0 or t >= M.CONTEST_SLOTS then return nil end
  local acc = {}
  for i, a in ipairs(args.accessories or {}) do
    if i > M.CONTEST_ACCESSORIES then break end
    acc[i] = { id = a.id, x = a.x, y = a.y, z = a.z }
  end
  local p = { full = true, mon = M.monCopy(args.mon), monX = args.monX, monY = args.monY, monZ = args.monZ, accessories = acc,
              backdrop = args.backdrop or 0, trainerName = args.trainerName,
              trainerGender = args.trainerGender or 0, rank = args.rank or 0, contestType = t,
              language = M.LANGUAGE_EN }
  l[t] = p
  return p
end

-- From the contest's end (Gen4Commands g4_end_contest, a won non-practice
-- contest): the player's contestant as the dress-up left it. The contest's
-- dress-up (src/ui/Gen4ContestDressUp.lua) keeps the Accessories that ended
-- up ON the Pokemon (ov22_0225768C, which is also what ov22_02256FD8 puts in
-- the contest photo), relative to the Pokemon's centre (192, MON_FOOT - 40);
-- the stage is the same (136, 16) one. No backdrop is chosen there: 0.
function M.contestWon(save, c)
  local e = c and c.contestants and c.contestants[0]
  if not (e and e.mon) then return nil end
  local D = require("src.ui.Gen4ContestDressUp")
  local cx, cy = D.MON_X, D.MON_FOOT - 40
  local acc = {}
  for _, a in ipairs(e.accessories or {}) do
    -- INFERRED priorities: the Accessories that joined are on the Pokemon,
    -- so in front of it, the last to join in front (ov22_02257DEC's rule)
    if a.accessory and a.x then acc[#acc + 1] = { id = a.accessory, x = cx + a.x - 136, y = cy + a.y - 16, z = -(#acc + 1) } end
  end
  for i, a in ipairs(acc) do a.z = -(#acc - i + 1) end
  return M.writeContest(save, c.type, { mon = e.mon, monX = cx - 136, monY = cy - 16, monZ = -(#acc + 1), accessories = acc,
    backdrop = 0, rank = c.rank, trainerName = save and save.player and save.player.name,
    trainerGender = save and save.player and save.player.gender == "girl" and 1 or 0 })
end

-- DressUpPhoto_SetTitle on photo 0: one easy-chat word; the slot need not
-- hold a photo (the title is written all the same)
function M.setTitle(save, word)
  local l = list(save, "dressUp")
  if not l then return end
  l[0] = l[0] or { full = false }
  l[0].title = tonumber(word)
end

return M
