local C = {}
function C.run(root, backend, version, api, format)
  local Fixture = dofile(root .. "/tests/held_content/fixture.lua")
  local rows = {}
  if require("src.core.GameVersion").generation(version) ~= 2 then
    local f = Fixture.new(root, backend, version, tonumber(api), format, "berry")
    local h = f.e.api.content.held_items
    f.T.eq(f.e.state.available, false, "reference has no held registry for this generation")
    f.T.eq(h:get("LEFTOVERS"), nil, "unavailable registry has no definitions")
    h:override("LEFTOVERS", { heldEffect = "HELD_BERRY", heldParameter = 7 })
    f.T.eq(f.data.items.LEFTOVERS.heldEffect, 3, "unavailable writes leave attributes intact")
    f.close()
    return { { mode = "unavailable", available = false } }
  end
  for _, mode in ipairs({
    "none",
    "berry",
    "patch",
    "remove",
    "register",
    "omitted",
    "custom",
    "price",
    "stack",
    "modern",
    "dragon",
    "delete_parameter",
    "rollback",
    "invalid",
    "no-mod",
  }) do
    local f = Fixture.new(root, backend, version, tonumber(api), format, mode)
    local failed = mode == "rollback" or (mode == "invalid" and tonumber(api) >= 2)
    f.T.eq(#f.result.errors > 0, failed, "held definition entry outcome " .. mode)
    local itemId = mode == "register" and "PORTABLE_ITEM"
      or mode == "modern" and "BERRY"
      or mode == "dragon" and "DRAGON_FANG"
      or "LEFTOVERS"
    local hp, item = f.run(itemId)
    local expected = ({
      berry = 107,
      register = 111,
      custom = 109,
      price = 117,
      remove = 100,
      omitted = 100,
      dragon = 100,
      modern = 107,
      stack = 109,
      invalid = tonumber(api) == 1 and 356 or 125,
    })[mode] or 125
    f.T.eq(hp, expected, "actual held definition residual " .. mode)
    local row = { mode = mode, hp = hp, held = item ~= nil, failed = failed }
    if f.e then
      f.T.eq(f.e.state.available, true, "native held registry available")
      local record = f.e.api.content.held_items:get(itemId)
      row.record = record
      if tonumber(api) >= 3 and record then
        record.heldParameter = 222
        f.T.check(f.e.api.content.held_items:get(itemId).heldParameter ~= 222, "API-3 read is detached")
        row.record = f.e.api.content.held_items:get(itemId)
      end
      if mode == "register" then
        f.T.eq(f.data.items.PORTABLE_ITEM.index, 240, "common item index retained")
      end
      if mode == "dragon" then
        local effect, parameter = f.read("DRAGON_FANG")
        f.T.eq(effect, "HELD_NONE", "explicit public definition overrides host name policy")
        row.nativeEffect, row.parameter = effect, parameter
      end
      local count = 0
      for id, value in f.e.api.content.held_items:each() do
        f.T.check(type(id) == "string" and type(value.heldEffect) == "string", "public held enumeration")
        count = count + 1
      end
      row.count = count
      if mode == "price" then
        f.T.eq(f.data.items[f.nativeItem("LEFTOVERS")].price, 999, "item price composes with held fields")
      end
    end
    rows[#rows + 1] = row
    f.close()
  end
  return rows
end
return C
