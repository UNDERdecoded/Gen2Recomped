local M = {}
function M.run(f)
  local T, e, rows = f.T, f.e, {}
  local function query(label, map, terrain, opts)
    local out, why =
      e.preview(map or "PROBE", terrain or "grass", opts or (f.generation == 2 and { daytime = "DAY" } or {}))
    T.check(out ~= nil, why or "preview succeeds")
    rows[#rows + 1] = { label = label, chance = out.chance, dist = out.dist }
    return out
  end
  local before = require("src.link.Json").encode(f.game.save)
  for _, terrain in
    ipairs(f.generation == 2 and f.api < 3 and { "grass", "water" } or { "grass", "water", "indoor" })
  do
    local calls = e.state.calls
    local out = query("base:" .. terrain, nil, terrain)
    T.eq(e.state.calls, calls + 1, "public query invokes preview seam once")
    T.eq(e.state.preview, true, "context marks preview")
    T.eq(e.state.mapId, "PROBE", "context has explicit queried map")
    T.eq(
      e.state.terrain,
      f.api >= 3 and terrain == "indoor" and "grass" or terrain,
      "context retains requested terrain"
    )
    T.eq(out.chance, f.generation == 3 and 1 / 9 or 20 / 256, "independent native rate")
    if f.generation == 3 then
      T.eq(type(e.state.opts), "table", "GBA forwards query options")
    else
      T.eq(e.state.opts, nil, "GB/Gold context retains reference option boundary")
    end
  end
  local baseline = query("baseline")
  for _, mode in ipairs({ "replace", "empty", "mutate", "post", "nil", "scalar" }) do
    e.state.mode = mode
    local out = query(mode)
    T.eq(out.chance, baseline.chance, "table transform cannot replace independent chance")
    if mode == "replace" then
      T.same(out.dist, { MEW = 7 }, "replacement distribution returned")
    elseif mode == "empty" then
      T.same(out.dist, {}, "empty distribution is accepted")
    elseif mode == "mutate" then
      T.same(out.dist, { MEW = 13 }, "mutated next arguments returned")
    elseif mode == "post" then
      T.eq(out.dist.MEW, 11, "downstream result can be transformed")
    else
      T.same(out.dist, baseline.dist, "non-table return falls back to detached distribution")
    end
  end
  e.state.mode = "pass"
  T.same(query("fresh").dist, baseline.dist, "prior callback writes cannot persist into native tables")
  if f.generation == 2 then
    local night = query("night", nil, "grass", { daytime = "NITE" })
    T.same(night.dist, { MEW = 100 }, "native Gold night table feeds hook")
    T.eq(night.chance, 40 / 256, "native Gold night rate remains independent")
    T.same(query("dark", nil, "grass", { daytime = "DARK" }), night, "Gold DARK is night")
  end
  query("empty map", "EMPTY")
  T.eq(e.state.mapId, "EMPTY", "empty native table still invokes preview hook")
  e.state.mode = "replace"
  local empty = query("empty replace", "EMPTY")
  T.eq(empty.chance, 0, "empty native map retains zero chance")
  T.same(empty.dist, { MEW = 7 }, "empty native map can expose custom preview weights")
  e.state.mode = "pass"
  local rate = f.land.rate
  f.setRate(0)
  local zero = query("zero rate")
  T.eq(zero.chance, 0, "zero native chance survives hook")
  T.same(
    zero.dist,
    f.generation == 3 and baseline.dist or {},
    "zero-rate distribution follows native generation"
  )
  f.setRate(rate)
  for _, after in ipairs({ false, true }) do
    local off = e.api.hooks:wrap("encounter.table", function(next, ...)
      if after then
        next(...)
      end
      error("intentional preview wrapper failure")
    end, 100)
    local calls = e.state.calls
    T.same(query("error:" .. tostring(after)), baseline, "wrapper error recovers native preview")
    T.eq(e.state.calls, calls + 1, "error recovery invokes downstream once")
    off()
  end
  if f.api >= 3 then
    local off = e.api.hooks:wrap("encounter.table", function(next, dist, ctx)
      local a, b = next(dist, ctx), next(dist, ctx)
      T.same(a, b, "repeated next retains distribution")
      return a
    end, 100)
    local calls = e.state.calls
    query("replay")
    T.eq(e.state.calls, calls + 1, "API-3 repeated next dispatches downstream once")
    off()
  end
  e.stop()
  e.stop()
  local calls = e.state.calls
  T.same(query("unsubscribed"), baseline, "unsubscribe restores native preview")
  T.eq(e.state.calls, calls, "unsubscribe retires callback")
  T.eq(require("src.link.Json").encode(f.game.save), before, "pure consumer leaves save untouched")
  return rows
end
return M
