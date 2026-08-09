-- Strict X.Y.Z semantic-version parsing and comparison for the self-updater.
-- Every part of the updater (Boot, Check, the release picker) agrees on this
-- one notion of "newer".  Zero requires and no love.* calls, so plain-Lua
-- tests can exercise it and Boot can use it during the earliest boot step.
--
-- We only need the numeric core (major.minor.patch): the engine field is a
-- bare X.Y.Z in shipped builds and the "0.0.0-dev" placeholder in the working
-- tree.  Pre-release / build metadata is intentionally not supported -- a
-- "-dev" or any other suffix makes parse fail, which is the safe answer for
-- the updater (a dev checkout never counts as a real release to chainload).

local Semver = {}

-- Parse a strict "X.Y.Z" string (an optional leading "v" is allowed) into
-- { major = n, minor = n, patch = n }.  Returns nil for anything else --
-- extra components, non-numeric parts, or a trailing suffix like "-dev".
function Semver.parse(s)
  if type(s) ~= "string" then return nil end
  local body = s:match("^v?(.+)$")
  if not body then return nil end
  local maj, min, pat = body:match("^(%d+)%.(%d+)%.(%d+)$")
  if not maj then return nil end
  return {
    major = tonumber(maj),
    minor = tonumber(min),
    patch = tonumber(pat),
  }
end

-- Coerce an argument that is either an already-parsed table or a version
-- string into a parsed table (or nil).
local function coerce(v)
  if type(v) == "table" then return v end
  return Semver.parse(v)
end

-- Compare two versions, each a parsed table or an X.Y.Z string.
-- Returns -1 when a < b, 0 when equal, 1 when a > b.  An unparseable side
-- sorts as the lowest possible version so a bogus value never wins a "newer"
-- test; two unparseable sides compare equal.
function Semver.compare(a, b)
  local pa, pb = coerce(a), coerce(b)
  if not pa and not pb then return 0 end
  if not pa then return -1 end
  if not pb then return 1 end
  for _, field in ipairs({ "major", "minor", "patch" }) do
    if pa[field] < pb[field] then return -1 end
    if pa[field] > pb[field] then return 1 end
  end
  return 0
end

return Semver
