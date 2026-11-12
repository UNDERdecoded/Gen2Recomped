-- Round 22: the item-get sequence as the cartridge runs it.
--
-- InitItemGetSequence (playerItemUtils.c) makes LINK_HOLDING_ITEM
-- (object/linkHoldingItem.c) and puts Link in PLAYER_ITEMGET (player.c):
--   PlayerItemGetInit   flipX off, animationState IdleSouth, the animation
--                       ANIM_GET_ITEM_SMALL ($2E0) / _BIG ($1B9) (or _NOCAP
--                       $45E / $45B) by IsMinishItem (gItemMetaData flags & 1);
--                       Minish Link keeps his animation.
--   LINK_HOLDING_ITEM   Action1 waits for Link's frame flags == $41: GiveItem
--                       and SFX_ITEM_GET (not for the elements) -- timer 0/1;
--                       Action2 waits for $42: MessageFromTarget(the item's
--                       textId; + heartPieces for a piece of heart; shells
--                       with type2 > 1 the message next to it) -- timer 0/2/5;
--                       the item is drawn while Link's frame has bit $40, at
--                       Link + GetSpriteSubEntryOffsetDataPointer(Link's sprite,
--                       frameIndex) bytes 0 / 1.
--   sub_08071038        ends when the message is closed AND the animation is
--                       done (frame bit $80): ResetPlayerAnimationAndAction.
-- The timer ("delay") argument: 0 = give, sound and message; 1 = give and
-- sound, no message; 3 = no give, no sound, no message, the item's
-- inventory value set to 2 when Link puts it down (Melari's broken sword).
--
-- In the port Field:giveItem still changes the inventory at once (callers
-- read it back the same frame); only the sound, the message and the held
-- item follow Link's frames.  While the message is still due,
-- Field:messageActive() is true, so scripts and NPCs waiting on the item
-- text keep waiting (the cartridge's gMessage is not active yet either,
-- but its callers wait on the player's ITEMGET state as well).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local IG = {}

local ANIM_BIG, ANIM_SMALL, ANIM_BIG_NOCAP, ANIM_SMALL_NOCAP = 0x1B9, 0x2E0, 0x45B, 0x45E
local SFX_ITEM_GET = 0x109
local ITEM_EARTH, ITEM_WIND = 0x40, 0x43 -- the four elements $40-$43
local ITEM_SHELLS, ITEM_HEART_PIECE = 0x3F, 0x63
local FALLBACK_MSG, FALLBACK_END = 8, 68 -- frames, when Link's animation has no flags (Minish Link)

IG.ANIM = { big = ANIM_BIG, small = ANIM_SMALL, bigNoCap = ANIM_BIG_NOCAP, smallNoCap = ANIM_SMALL_NOCAP }

local function meta(f, item)
  local m = f.assets and f.assets.manifest and f.assets.manifest.itemMeta
  return m and m[item]
end

-- IsMinishItem: gItemMetaData[item] byte 3 bit 0
function IG.isMinishItem(f, item)
  local m = meta(f, item)
  return m ~= nil and band(m.flags or 0, 1) ~= 0
end

function IG.animFor(f, item, hasCap)
  local small = IG.isMinishItem(f, item)
  if hasCap then return small and ANIM_SMALL or ANIM_BIG end
  return small and ANIM_SMALL_NOCAP or ANIM_BIG_NOCAP
end

-- the message LinkHoldingItem_Action2 shows (0 = none)
function IG.messageFor(f, item, type2, pieceCount)
  local m = meta(f, item)
  local idx = m and m.text or 0
  if idx == 0 then return 0 end
  if item == ITEM_HEART_PIECE then idx = idx + (pieceCount or 0)
  elseif item == ITEM_SHELLS and (type2 or 0) > 1 then
    if idx == 0x577 then idx = idx - 1 else idx = idx + 1 end
  end
  return idx
end

-- start the sequence; `delay` is InitItemGetSequence's third argument
function IG.start(f, item, type2, delay, pieceCount)
  local p = f.player
  delay = delay or 0
  local msg = (delay == 0 or delay == 2 or delay == 5) and IG.messageFor(f, item, type2, pieceCount) or 0
  if msg ~= 0 and not (f.assets and f.assets:message(msg)) then msg = 0 end
  local sound = delay <= 2 and not (item >= ITEM_EARTH and item <= ITEM_WIND)
  if not p then
    if sound then f:sound(SFX_ITEM_GET) end
    if msg ~= 0 then f.messageRupees = type2; f:message(msg) end
    return
  end
  p.state = "itemget"
  p.heldItem = item
  p.itemGetHold = nil
  p.itemGet = { item = item, type2 = type2, delay = delay, msg = msg, sound = sound, action = 1, ticks = 0 }
  if not p.minish then
    p.animationState = 4 -- IdleSouth
    p.entFlip = false
    p:setAnim(IG.animFor(f, item, p.hasCap and true or false), true)
    p.entFlip = false
  end
end

-- true while the item's message is still to come (Field:messageActive)
function IG.pending(f)
  local p = f.player
  local ig = p and p.state == "itemget" and p.itemGet
  return ig and ig.action < 3 and ig.msg ~= 0 or false
end

local function fire(f, p, ig, flagsOk)
  -- Action1: frame flags $41
  if ig.action == 1 and flagsOk(0x41) then
    ig.action = 2
    if ig.sound then f:sound(SFX_ITEM_GET) end
  end
  -- Action2: frame flags $42
  if ig.action == 2 and flagsOk(0x42) then
    ig.action = 3
    if ig.msg ~= 0 then
      f.messageRupees = ig.type2
      f:message(ig.msg)
    end
  end
end

-- PLAYER_ITEMGET's per-frame update (Player:update's "itemget" branch)
function IG.update(f, p)
  local ig = p.itemGet
  if not ig then
    -- an item get started some other way: the round-8 behaviour
    p.anim:update(1)
    if not f:messageActive() then
      p.itemGetHold = (p.itemGetHold or 0) + 1
      if p.itemGetHold > 4 then p.state = "normal"; p.heldItem = nil; p.itemGetHold = nil end
    end
    return
  end
  p.anim:update(1) -- UpdateAnimationSingleFrame
  ig.ticks = ig.ticks + 1
  local an = p.anim
  local hasFlags = p.animId == IG.animFor(f, ig.item, true) or p.animId == IG.animFor(f, ig.item, false)
  if hasFlags then
    fire(f, p, ig, function(v) return band(an.flags or 0, 0x7F) == v end)
  else
    fire(f, p, ig, function(v) return ig.ticks >= (v == 0x41 and FALLBACK_MSG / 2 or FALLBACK_MSG) end)
  end
  if ig.action < 3 or f:messageActive() then return end
  local done
  if hasFlags then done = an.done or band(an.flags or 0, 0x80) ~= 0 else done = ig.ticks >= FALLBACK_END end
  if not done then return end
  -- LinkHoldingItem_Action3 (timer 3: the item's inventory value 2)
  if ig.delay == 3 then f.save.items[ig.item] = 2 end
  p.itemGet = nil
  p.heldItem = nil
  p.state = "normal"
  -- ResetPlayerAnimationAndAction
  p:setAnim(p:animFor("idle"), true)
end

-- the held item: shown while Link's frame flags have bit $40, placed by
-- his frame's sub-entry offset bytes (signed)
local EFO = 0x089FB770
function IG.itemOffset(f, sprite, frame)
  local R = require("src.zelda.tmc.NpcParts").readers(f.assets)
  if not R then return 0, -22 end
  local X = R.x
  local ok, ox, oy = pcall(function()
    local v = X.u16(EFO + 0x10 + 2 * sprite) + EFO
    local idx = X.u8(v + band(frame, 0xFF)) * 4
    local pnt = EFO + X.u32(EFO) + idx
    local a, b = X.u8(pnt), X.u8(pnt + 1)
    if a >= 128 then a = a - 256 end
    if b >= 128 then b = b - 256 end
    return a, b
  end)
  if not ok then return 0, -22 end
  return ox, oy
end

function IG.drawHeld(p, x, y)
  local f = p.field
  local ig = p.itemGet
  if ig then
    local hasFlags = p.animId == IG.animFor(f, ig.item, true) or p.animId == IG.animFor(f, ig.item, false)
    if hasFlags and band(p.anim.flags or 0, 0x40) == 0 then return end
    if hasFlags then
      local ox, oy = IG.itemOffset(f, p:sprite(), p.anim.frame or 0)
      f:objects():drawItemIcon(p.heldItem, x + ox, y + oy)
      return
    end
  end
  f:objects():drawItemIcon(p.heldItem, x, y - 22)
end

return IG
