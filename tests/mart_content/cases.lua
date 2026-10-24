local C = {}
function C.run(root, backend, version, api, format)
  local Fixture = dofile(root .. "/tests/mart_content/fixture.lua")
  local rows = {}
  local V = require("src.core.GameVersion")
  if V.generation(version) ~= 2 then
    local f = Fixture.new(root, backend, version, api, format, "none")
    f.T.eq(f.e.available, false, "mart contract unavailable outside Gen 2")
    f.close()
    return { { mode = "unavailable", available = false } }
  end
  for _, mode in ipairs({
    "none",
    "replace",
    "empty",
    "remove",
    "register",
    "price",
    "zero",
    "maximum",
    "delete",
    "stack",
    "rollback",
    "invalid",
    "no-mod",
  }) do
    local f = Fixture.new(root, backend, version, api, format, mode)
    f.T.eq(
      #f.result.errors > 0,
      mode == "rollback" or mode == "invalid" or (mode == "delete" and api >= 2),
      "mart entry outcome " .. mode
    )
    local row = { mode = mode, failed = #f.result.errors > 0 }
    local m = f.e and f.e.api.content.marts
    if m then
      f.T.eq(m:get("34"), nil, "unknown string ID reads as absent")
      f.T.eq(m:get("generation"), nil, "metadata is not a shelf")
      row.stock = m:get("0")
      row.bargain = m:get("bargain")
      row.last = m:get("33")
      local count = 0
      for id in m:each() do
        f.T.check(id == "0" or id == "33" or id == "bargain", "enumeration excludes metadata")
        count = count + 1
      end
      row.count = count
      if api == 3 and row.stock then
        row.stock[1] = "CORRUPTED"
        row.stock = m:get("0")
        f.T.check(row.stock[1] ~= "CORRUPTED", "unified read detached")
      end
    end
    row.money, row.countBought, row.sold, row.unitPrice = f.purchase(false, 2)
    row.bargainMoney, row.bargainCount, row.bargainSold, row.bargainPrice = f.purchase(true, 1)
    local native = f.shelf("0")
    if mode == "empty" or mode == "remove" or (mode == "delete" and api == 1) then
      f.T.same(native, {}, "empty and tombstoned shelves stay empty")
    end
    if mode == "replace" then
      f.T.eq(row.money, 97600, "normal purchase uses item price")
      f.T.eq(row.bargainMoney, 99500, "bargain has its own price")
      f.T.eq(row.bargainCount, 1, "bargain item bought only once")
    end
    rows[#rows + 1] = row
    f.close()
  end
  return rows
end
return C
