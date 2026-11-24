-- Round 49: per-object error guard for the TMC game loop.
--
-- One object's Lua error used to end the whole update: the runtime's
-- Host:_call caught it and stopped the game on the error screen (round 48's
-- frozen Armos: bxor(nil) every frame).  In the real runtime (game.opts.host
-- set) each enemy / dungeon object / manager update now runs guarded: the
-- first time a distinct error happens it is logged once -- object kind, id,
-- form, room and the traceback -- through Game:log and the host's warning
-- log, and kept in f.objErrors (count of repeats); the object is skipped for
-- that frame and the player's game goes on.  Without a host (the unit tests)
-- or with TMC_STRICT_ERRORS set, errors are raised as before, so a test can
-- never pass over a broken object.
local M = {}

M.MAX = 64 -- distinct errors kept per field

local function strict(f)
  if os.getenv and os.getenv("TMC_STRICT_ERRORS") then return true end
  local g = f and f.game
  return not (g and g.opts and g.opts.host)
end
M.strict = strict

local function hex(v) return type(v) == "number" and string.format("%02X", v) or tostring(v) end

-- record one failure of object e (what = "enemy" / "object" / "manager")
function M.record(f, what, e, err)
  f.objErrors = f.objErrors or {}
  local msg = tostring(err)
  local first = msg:match("^[^\n]*") or msg
  local key = string.format("%s:%s:%s:%s", what, hex(e and e.kind), hex(e and e.id), first)
  local seen = f._objErrIdx and f._objErrIdx[key]
  if seen then seen.count = seen.count + 1 return seen end
  f._objErrIdx = f._objErrIdx or {}
  local r = f.room
  local rec = { key = key, what = what, kind = e and e.kind, id = e and e.id, form = e and (e.form or e.type),
    x = e and e.x and math.floor(e.x), y = e and e.y and math.floor(e.y),
    area = r and r.area, room = r and r.room, msg = first, trace = msg, count = 1, frame = f.frame }
  f._objErrIdx[key] = rec
  if #f.objErrors < M.MAX then f.objErrors[#f.objErrors + 1] = rec end
  local line = string.format("object error (%s kind %s id %s form %s at %s,%s room %s:%s): %s",
    what, hex(rec.kind), hex(rec.id), tostring(rec.form), tostring(rec.x), tostring(rec.y), hex(rec.area), hex(rec.room), msg)
  if f.game and f.game.log then pcall(f.game.log, f.game, line) end
  local okL, Logger = pcall(require, "src.core.Logger")
  if okL and type(Logger) == "table" and Logger.warn then pcall(Logger.warn, "%s", line) else print("[tmc] " .. line) end
  return rec
end

-- run fn(a, b, c) for object e; true when it ran without an error
function M.call(f, what, e, fn, a, b, c)
  if strict(f) then fn(a, b, c) return true end
  local ok, err = xpcall(fn, debug.traceback, a, b, c)
  if ok then return true end
  M.record(f, what, e, err)
  return false
end

return M
