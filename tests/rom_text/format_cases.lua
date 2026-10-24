local C = {}
function C.run()
  local T, format = require("tests.modkit"), require("src.core.RomText")
  local rows = {}
  local cases = {
    { "plain", "Native", "fallback", {} },
    { "no-fallback", "Native", nil, {} },
    { "false-prose", false, "fallback", {} },
    { "missing", nil, "fallback %s", { "VALUE" } },
    { "one-slot", "{USER} wakes!", "%s fallback", { "GOLD" } },
    { "two-slots", "{USER} used {MOVE}!", "%s/%s fallback", { "GOLD", "TACKLE" } },
    { "defer-player", "{PLAYER} watches {USER}", "%s fallback", { "GOLD" } },
    { "fill-player", "{PLAYER} watches {USER}", "%s/%s fallback", { "PROBE", "GOLD" } },
    { "defer-both", "{PLAYER} {USER} {RIVAL}", "%s fallback", { "GOLD" } },
    { "named", "{PLAYER} {USER} {RIVAL}", "fallback", { { USER = "GOLD" } } },
    { "named-braces", "{USER}/{TARGET}", "fallback", { { ["{USER}"] = "GOLD", TARGET = 42 } } },
    { "named-missing", "{USER}/{TARGET}", "fallback", { {} } },
    { "named-false", "{USER}/{TARGET}", "fallback", { { USER = false, TARGET = 0 } } },
    { "done", "{USER} wakes!{DONE}", "%s fallback", { "GOLD" } },
    { "prompt", "{USER} wakes!{PROMPT}", "%s fallback", { "GOLD" } },
    { "endings-defer", "{PLAYER} watches {USER}{DONE}", "%s fallback", { "GOLD" } },
    { "endings-named", "{USER}{DONE}", "fallback", { { USER = "GOLD", DONE = "literal" } } },
    { "mismatch", "Native", "%s fallback", { "GOLD" } },
    { "percent-literal", "100% Native", "fallback", {} },
    { "printf-is-not-a-slot", "%s wakes!", "%s fallback", { "GOLD" } },
    { "broken-tag", "prefix {USER", "%s fallback", { "GOLD" } },
    { "slots-percent", "{USER} has 100%", "%s fallback", { "GOLD" } },
    { "missing-required", nil, nil, {} },
    { "mismatch-required", "Native", nil, { "GOLD" } },
  }
  for _, case in ipairs(cases) do
    local name, native, fallback, args = unpack(case)
    local data = { text = { TEST = native } }
    local ok, result = pcall(format, data, "TEST", fallback, unpack(args))
    local failed = name == "missing-required" or name == "mismatch-required"
    T.eq(ok, not failed, "native formatter outcome " .. name)
    if not ok then
      T.check(tostring(result):find("ROM text TEST", 1, true) ~= nil, "missing prose names its native label")
    end
    T.eq(data.text.TEST, native, "formatting leaves source text intact")
    rows[#rows + 1] = { name = name, ok = ok, text = ok and result or nil }
  end
  return rows
end
return C
