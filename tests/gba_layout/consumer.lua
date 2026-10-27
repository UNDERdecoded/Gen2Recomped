-- One unmodified Gen1 module consumer, also run on the original public host.
return function(Layout)
  local checks, signature = 0, {}
  local function check(ok, label)
    checks = checks + 1; assert(ok, label or ("layout check " .. checks))
  end
  local oldView = package.loaded["src.core.game3.field_view"]
  local oldAssets = package.loaded["src.render.Assets"]
  local events = {}
  local view = { invalidateLayoutCell = function(layout, x, y) events[#events + 1] = { layout, x, y } end }
  package.loaded["src.core.game3.field_view"] = view
  package.loaded["src.render.Assets"] = nil
  local base = { { mid = 10, coll = 0, elev = 15 }, { mid = 11, coll = 7, elev = 0 }, { mid = 12 } }
  local blob = string.rep("\0", 14) .. string.char(2, 2) .. string.rep("\0", 100)
  local decoded = { width = 4, height = 2, trueWidth = 3, trueHeight = 1,
    borderWidth = 2, borderHeight = 2, borderMids = { 21, 22, 23, 24 }, cells = base }
  local layout = Layout.fromDecoded(decoded, "CUSTOM", "PAIR", blob)
  check(layout.cells == base and layout.borderMids == decoded.borderMids, "decoded source retains identity")
  check(layout.mapId == "CUSTOM" and layout.pair == "PAIR")
  check(layout:cellAt(0, 0) == base[1], "base cells are borrowed")
  check(layout:midAt(0, 0) == 10 and layout:collAt(0, 0) == 0 and layout:elevAt(0, 0) == 15)
  check(layout:collAt(2, 0) == nil and layout:elevAt(2, 0) == nil, "present partial cells keep missing fields")
  for y = -3, 3 do for x = -3, 6 do
    local cell = layout:cellAt(x, y)
    check(layout:midAt(x, y) == cell.mid, "border/padding mid")
    check(layout:collAt(x, y) == cell.coll, "border/padding collision")
    check(layout:elevAt(x, y) == cell.elev, "border/padding elevation")
    signature[#signature + 1] = tostring(cell.mid) .. ":" .. tostring(cell.coll) .. ":" .. tostring(cell.elev)
  end end
  local source = layout:workerPacked()
  check(source.blob == blob and source.off == 25 and source.width == 4 and source.trueWidth == 3)
  check(source.borderMids ~= layout.borderMids and source.borderMids[4] == 24, "worker border snapshot is detached")
  layout:applyOverride("0", "0", "99", 0, 0)
  check(layout:midAt(0, 0) == 99 and layout:collAt(0, 0) == 0 and layout:elevAt(0, 0) == 0)
  check(base[1].mid == 10 and base[1].elev == 15, "override never mutates decoded source")
  check(layout._revision == 1 and #events == 1 and events[1][1] == layout)
  local packed = layout:workerPacked()
  check(packed.overrides[0].mid == 99 and packed.overrides[0] ~= layout.overrides[0])
  layout:applyOverride(0, 0, 100, 1, 2)
  check(packed.overrides[0].mid == 99, "published worker snapshot does not follow writes")
  local before = layout._revision
  check(layout:setMetatiles({ { x = 1, y = 0, mid = 90 }, { x = 1, y = 0, coll = 0 }, { x = 1, y = 0, elev = 15 } }) == 3)
  check(layout._revision == before + 1, "one batch revision")
  check(layout:midAt(1, 0) == 90 and layout:collAt(1, 0) == 0 and layout:elevAt(1, 0) == 15, "duplicate rows compose in order")
  before = layout._revision; check(layout:setMetatiles({}) == 0 and layout._revision == before)
  layout.overrides[2] = { mid = 30 }
  check(layout:collArray()[3] == 255, "missing source and override collision stays blocked")
  layout.overrides[1] = { mid = 31 }
  check(layout:collArray()[2] == 7, "partial override falls back to base collision array")
  layout:applyOverride(3, 0, 40, 0, 15)
  check(layout:cellAt(3, 0).coll == 0 and layout:collArray()[4] == 255, "outside override never admits padded collision")
  local originalCellAt = layout.cellAt
  layout.cellAt = function() return { mid = 301, coll = 302, elev = 303 } end
  check(layout:midAt(-8, -8) == 301 and layout:collAt(-8, -8) == 302 and layout:elevAt(-8, -8) == 303)
  check(layout:workerPacked() == nil, "custom sampling disables original packed source")
  layout.cellAt = originalCellAt
  local midAt = layout.midAt; layout.midAt = function() return 7 end
  check(layout:workerPacked() == nil, "custom mid sampler disables packed source")
  layout.midAt = midAt
  layout.trueWidth = 2; check(layout:workerPacked() == nil); layout.trueWidth = 3
  local cells = layout.cells; layout.cells = {}; check(layout:workerPacked() == nil); layout.cells = cells
  package.loaded["src.render.Assets"] = { loader = { overrideOrder = function() return { "custom" } end } }
  check(layout:workerPacked() == nil, "asset overrides disable original packed bytes")
  package.loaded["src.render.Assets"] = nil
  view._nativeDirty = nil; events = {}
  local rows = {}; for x = 1, 64 do rows[x] = { x = x, y = 2, mid = x } end
  layout:setMetatiles(rows); check(#events == 64 and not view._nativeDirty, "64 writes invalidate individual cells")
  rows[65] = { x = 65, y = 2, mid = 65 }; events = {}; layout:setMetatiles(rows)
  check(#events == 0 and view._nativeDirty == true, "larger batch requests full redraw")
  view._nativeDirty = nil
  local stamp = { width = 3, height = 2, trueWidth = 2, trueHeight = 1,
    cells = { { mid = 400, coll = 0, elev = 15 }, { mid = 401, coll = 7 }, { mid = 999 } } }
  before = layout._revision
  check(layout:stamp(stamp, 0, 0) == 2 and layout._revision == before + 1)
  check(layout:midAt(0, 0) == 400 and layout:elevAt(0, 0) == 15 and layout:elevAt(1, 0) == 0)
  check(stamp.cells[1].mid == 400 and layout.overrides[0] ~= stamp.cells[1], "stamped cells are copied")
  check(view._nativeDirty == true)
  before = layout._revision; layout:clearOverrides()
  check(layout._revision == before + 1 and next(layout.overrides) == nil and layout:midAt(0, 0) == 10)
  before = layout._revision; layout:clearOverrides(); check(layout._revision == before, "empty clear preserves revision")
  local empty = Layout.fromDecoded({}, "EMPTY")
  check(empty.pair == "sevii_outdoor" and empty:collArray() == nil and empty:workerPacked() == nil)
  check(empty:cellAt(4, 2).coll == 255 and empty:midAt(-4, -2) == 0)
  package.loaded["src.core.game3.field_view"] = oldView
  package.loaded["src.render.Assets"] = oldAssets
  return checks, table.concat(signature, ",")
end
