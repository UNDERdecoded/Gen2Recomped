local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/effects%.lua$")
  return dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, "effects")
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local report = f.exports.report()
  assert(report.initial == "NO_ADDITIONAL_EFFECT" and report.final == "SLEEP_EFFECT")
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
