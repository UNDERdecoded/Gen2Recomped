local M = {}
function M.run(f, version)
  local T, e, rows = f.T, f.e, {}
  local function eq(actual, expected, label)
    T.eq(actual, expected, label)
    rows[#rows + 1] = { case = label, value = actual }
  end
  local a, b = f.game("first"), f.game("second")
  local context = assert(e.context(a))
  eq(context.gameVersion, version, "context version")
  eq(context.playthroughId, "first", "context identity")
  eq(type(context.engineVersion), "string", "context engine version")
  eq(context.root, nil, "no private root")
  eq(e.write(a, "state/value", { n = 7, nested = { ready = true } }), true, "write record")
  local got = assert(e.read(a, "state/value"))
  got.nested.ready = false
  eq(e.read(a, "state/value").nested.ready, true, "decoded copy isolation")
  local _, code = e.read(b, "state/value")
  eq(code, "not_found", "playthrough isolation")
  _, code = f.other.read(a, "state/value")
  eq(code, "not_found", "mod isolation")
  local otherVersion = f.game("first")
  otherVersion.save.version = version == "red" and "blue" or "red"
  _, code = e.read(otherVersion, "state/value")
  eq(code, "not_found", "version isolation")
  local bytes = "CACHE\0\255\128 return MALICIOUS = true"
  eq(e.writeBytes(a, "state/bytes", bytes), true, "write bytes")
  eq(e.readBytes(a, "state/bytes") == bytes, true, "opaque byte roundtrip")
  _, code = e.read(a, "state/bytes")
  eq(code, "type_mismatch", "record-byte read mismatch")
  _, code = e.write(a, "state/bytes", {})
  eq(code, "type_conflict", "record cannot replace bytes")
  _, code = e.writeBytes(a, "state/value", "x")
  eq(code, "type_conflict", "bytes cannot replace record")
  eq(e.writeBytes(a, "state/empty", ""), true, "empty bytes write")
  eq(e.readBytes(a, "state/empty"), "", "empty bytes read")
  for _, key in ipairs({ "", "../escape", "/absolute", "double//slash", "tail/", "a.b", "a\\b" }) do
    local ok
    ok, code = e.write(a, key, {})
    eq(ok, false, "reject key " .. key)
    eq(code, "invalid_key", "key error " .. key)
  end
  local ok
  ok, code = e.write(a, "bad/value", { callback = function() end })
  eq(ok, false, "reject executable data")
  eq(code, "encode_failed", "data-only error")
  eq(
    table.concat(assert(e.list(a, "state")), ","),
    "state/bytes,state/empty,state/value",
    "sorted unique listing"
  )
  eq(table.concat(assert(e.list(a, "state/value")), ","), "state/value", "exact-key prefix")
  local main
  for path in pairs(f.files) do
    if path:match("/first/portable_storage/state/value%.lua$") then
      main = path
    end
  end
  assert(main, "native persisted record missing")
  f.files[main] = "corrupt"
  eq(e.read(a, "state/value").n, 7, "backup recovery")
  f.fs.fail = ".tmp"
  ok, code = e.write(a, "state/value", { n = 8 })
  eq(ok, false, "staging failure")
  eq(code, "write_failed", "staging error")
  f.fs.fail = ".lua"
  ok, code = e.write(a, "state/value", { n = 9 })
  eq(ok, false, "replacement failure")
  eq(code, "write_failed", "replacement error")
  f.fs.fail = nil
  eq(e.read(a, "state/value").n, 7, "failed write retains data")
  a.stack = { states = { { screenId = "TitleState" } } }
  local selected = assert(e.selected(a))
  eq(selected:context().playthroughId, "first", "selected context")
  eq(selected:read("state/value").n, 7, "selected read")
  local detached = selected:context()
  detached.playthroughId = "second"
  a.save.meta.playthroughId = "second"
  eq(selected:read("state/value").n, 7, "selected facade cannot be rerouted")
  _, code = selected:read(b, "state/value")
  eq(code, "invalid_key", "selected rejects injected game")
  _, code = e.selected(b)
  eq(code, "not_at_title", "selected title guard")
  local empty = f.game(nil)
  empty.stack = a.stack
  _, code = e.selected(empty)
  eq(code, "no_selected_playthrough", "selected does not allocate")
  eq(e.delete(f.game("first"), "state/value"), true, "delete record")
  _, code = selected:read("state/value")
  eq(code, "not_found", "delete removes recovery copies")
  eq(e.delete(f.game("first"), "state/bytes"), true, "delete bytes")
  _, code = e.readBytes(f.game("first"), "state/bytes")
  eq(code, "not_found", "delete removes byte recovery")
  return rows
end
return M
