-- Round 45: items for sale (ITEM_FOR_SALE, object 2) and the script commands
-- that sell them.  Syrup's Wake-Up Mushroom (the Witch Hut, $24:00) is the
-- first one on the main route.  An R27A module (spawnObject / frame).
--
-- CARTRIDGE BEHAVIOUR (src/object/itemForSale.c, src/playerUtils.c
-- AddInteractableShopItem / the INTERACTION_LIFT_SHOP_ITEM case, src/script.c
-- ScriptCommand_HasRoomItemForSale / ScriptCommand_BuyItem, itemUtils.c
-- GetItemPrice):
--   * The item (its type = the item id, type2 its parameter, timer 1 = the
--     small hitbox and every facing) sits on the counter, drawn as the
--     item's ground picture (sub_08080CB4), interactable (kind 8).
--   * Taken while nothing is held (gRoomVars.shopItemType == 0):
--     shopItemType / shopItemType2 = its type / type2, Link holds it over
--     his head (heldObject 4, carriedEntity).
--   * Held: facing someone to talk to (the interaction's kind 1) A / R
--     talks; otherwise A / B / R puts it back on its spot (sub_080819B4:
--     shopItemType = 0).  Once shopItemType is 0 while it is held (sold) it
--     is deleted.
--   * HasRoomItemForSale: condition = shopItemType != 0.
--   * BuyItem item, type2 (item 0 = the held one): GetItemPrice (gUnk_080FD964
--     [item].itemPrice, read from the ROM) <= rupees -> ModRupees(-price),
--     InitItemGetSequence(item, type2), shopItemType = 0; condition = paid.
-- SIMPLIFIED: Link carries it with the port's carry state (ANIM_PICKUP /
--   the carry walk); type $36 (the Stockwell dog-food special case) is not
--   modelled.
local bit = require("bit")
local bor = bit.bor

local M = {}

M.OBJ = 0x02 -- ITEM_FOR_SALE

local function price(f, item)
  local s = require("src.zelda.tmc.Story27Town2").shopEntry(f, item)
  return s and s.price or nil
end
M.price = price

local function backHome(f, e)
  e.x, e.y, e.z = e.homeX, e.homeY, 0
  e.hidden, e.talkable, e.interactType = false, true, 0
  e.carried = nil
end

local hook = {}
-- A / B / R while held: talk to the one in front, else put it back
local function talkTarget(f, p)
  local HB = require("src.zelda.tmc.Hitboxes")
  for _, o in ipairs(f.entities) do
    if o.talkable and not o.hidden and not o.deleted and not o.forSale45 and o.kind == 7 and HB.interactHit(f, p, o) then return o end
  end
end
M.talkTarget = talkTarget
function hook.throw(f, p, c)
  local t = talkTarget(f, p)
  if t then
    t.interactType = 1
    p.shopRestore45 = true -- Player:update turns "carry" into "throw" after this call
    return
  end
  p.carried = nil
  f.shopItem, f.shopItem2 = 0, 0
  backHome(f, c.ent)
end
function hook.drop(f, p, c)
  p.carried = nil
  f.shopItem, f.shopItem2 = 0, 0
  backHome(f, c.ent)
end
M.hook = hook

function M.spawnObject(d, e)
  if e.id ~= M.OBJ then return nil end
  local f = d.field
  local O = f:objects()
  local item = e.form or 0
  local def = O:def(0, item) -- the item's GROUND_ITEM picture
  if def then O:dress(e, def, item) end
  e.objAnim = item
  e.forSale45 = true
  e.homeX, e.homeY = e.x, e.y
  e.layer = 1
  e.talkable = true -- AddInteractableShopItem
  e.extUpdate = function(dd, me) M.update(dd.field, me) end
  d:track(e)
  return e
end

function M.update(f, e)
  local p = f.player
  if e.carried then
    -- sold: shopItemType went back to 0 while held
    if (f.shopItem or 0) == 0 then
      e.deleted = true
      if p.carried and p.carried.ent == e then p.carried = nil; if p.state == "carry" then p.state = "normal" end end
    end
    return
  end
  if (e.interactType or 0) ~= 0 then
    e.interactType = 0
    if (f.shopItem or 0) ~= 0 or p.carried or p.minish then return end
    f.shopItem, f.shopItem2 = e.form or 0, e.type2 or 0
    e.carried, e.hidden, e.talkable = true, true, false
    f:objects():lift(p, { obj = 0, form = e.form, ent = e, hook = hook, shop45 = true, def = f:objects():def(0, e.form) })
  end
end

-- gRoomVars is cleared with every room
function M.roomInit(f) f.shopItem, f.shopItem2 = 0, 0 end

function M.frame(f, input)
  local p = f.player
  if p and p.shopRestore45 then
    p.shopRestore45 = nil
    if p.carried and p.carried.shop45 and p.state == "throw" then
      p.state = "carry"; p.timer = 0
      p:setAnim(p.hasCap and 0x338 or 0x928, true)
    end
  end
  return false
end

-- ScriptCommand_BuyItem (command $1E)
local function install()
  local Script = require("src.zelda.tmc.Script")
  local C = Script.commands
  if C and not C[0x1E] then
    C[0x1E] = function(e, ctx, host)
      local item, t2 = ctx.mem:u16(ctx.ip + 2), ctx.mem:u16(ctx.ip + 4)
      if item == 0 then item, t2 = host.shopItem or 0, host.shopItem2 or 0 end
      local pr = price(host, item)
      local ok = pr ~= nil and pr <= (host.save.stats.rupees or 0)
      ctx.condition = ok and 1 or 0
      if ok then
        host:modStat("rupees", -pr)
        host:giveItem(item, t2)
        host.shopItem, host.shopItem2 = 0, 0
      end
      Script.active.flags = bor(Script.active.flags, 1)
    end
  end
end
install()
M.install = install

return M
