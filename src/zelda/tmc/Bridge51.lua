-- Round 51: BRIDGE_MANAGER ($05) taking its bridge back (src/manager/bridgeManager.c).
--
-- BridgeManager_Action1 (type2 bit 7 clear) every 8 frames: flag set ->
-- one more tile (up to the length); flag clear with tiles out ->
-- RestorePrevTileEntity on the last tile, the head steps back
-- (gUnk_08108034), SFX_HEART_GET.  $58:12's bridge is held out by a
-- PULLABLE_LEVER whose flag clears once the handle slides back home, so it
-- shrinks again (the cartridge's "dash across with the Pegasus Boots").  The
-- port built it and never took it back.  M.remember keeps the cell's map entry
-- (and type-only override) before a tile is laid; M.retract puts it back.
local M = {}

local function key(m) return m.cx .. ":" .. m.cy end

function M.remember(f, m)
  local r = f.room
  local name = m.layer == 2 and "top" or "bottom"
  local i = m.cy * r.tw + m.cx
  m.prev51 = m.prev51 or {}
  m.prev51[key(m)] = { mt = r.maps[name][i], to = r.typeOnly and r.typeOnly[name .. i] }
end

-- returns true when a tile was taken back
function M.retract(f, m)
  if (m.built or 0) <= 0 then return false end
  local r = f.room
  local name = m.layer == 2 and "top" or "bottom"
  local pv = m.prev51 and m.prev51[key(m)]
  if pv and pv.mt then
    r:setTile(m.layer, m.cx, m.cy, pv.mt)
    if pv.to then r.typeOnly = r.typeOnly or {} r.typeOnly[name .. (m.cy * r.tw + m.cx)] = pv.to end
    m.prev51[key(m)] = nil
  end
  m.cx, m.cy = m.cx - m.dx, m.cy - m.dy
  m.built = m.built - 1
  return true
end

return M
