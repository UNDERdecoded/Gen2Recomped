-- Pure-logic coverage for the self-updater (src/update/*).  Every export
-- exercised here is love-free: Semver's parse/compare, Boot's select()
-- decision function, and Check's release-JSON / sha256sums / asset parsers.
-- The love-bound halves (Boot.run's mount+chainload, Check's thread worker,
-- curl, hashing) need a real LOVE process and are covered elsewhere; this
-- suite is the plain-Lua seam the whole updater trusts.
--   luajit tests/engine/update_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Semver = require("src.update.Semver")
local Boot = require("src.update.Boot")
local Check = require("src.update.Check")
local Json = require("src.link.Json")

-- ---------------------------------------------------------------------------
-- Semver.parse
-- ---------------------------------------------------------------------------

-- valid triples decode to numeric fields, not strings
local p = Semver.parse("1.2.3")
check(p ~= nil, "parse accepts a plain X.Y.Z")
eq(p.major, 1, "parse major")
eq(p.minor, 2, "parse minor")
eq(p.patch, 3, "parse patch")
eq(type(p.major), "number", "parse yields numbers, not strings")

local zero = Semver.parse("0.0.0")
eq(zero.major, 0, "parse zeros: major")
eq(zero.patch, 0, "parse zeros: patch")

local big = Semver.parse("10.20.30")
eq(big.major, 10, "parse multi-digit major")
eq(big.minor, 20, "parse multi-digit minor")
eq(big.patch, 30, "parse multi-digit patch")

-- an optional leading lowercase "v" is stripped
local v = Semver.parse("v2.5.9")
check(v ~= nil, "parse accepts a leading v")
eq(v.major, 2, "leading v: major")
eq(v.minor, 5, "leading v: minor")
eq(v.patch, 9, "leading v: patch")

-- rejects: partial versions, extra components, non-numeric parts, suffixes,
-- a bare v, whitespace, empties, and non-string inputs -- all return nil, not
-- a raise (the safe answer for the updater is "not a real version")
eq(Semver.parse("1.2"), nil, "parse rejects a two-part version")
eq(Semver.parse("1"), nil, "parse rejects a one-part version")
eq(Semver.parse("1.2.3.4"), nil, "parse rejects a four-part version")
eq(Semver.parse("1.2.x"), nil, "parse rejects a non-numeric part")
eq(Semver.parse("1.2.3-dev"), nil, "parse rejects a pre-release suffix")
eq(Semver.parse("0.0.0-dev"), nil, "parse rejects the working-tree placeholder")
eq(Semver.parse("v"), nil, "parse rejects a bare v")
eq(Semver.parse(" 1.2.3"), nil, "parse rejects leading whitespace (anchored)")
eq(Semver.parse("1.2.3 "), nil, "parse rejects trailing whitespace (anchored)")
eq(Semver.parse(""), nil, "parse rejects the empty string")
eq(Semver.parse("nightly"), nil, "parse rejects a non-numeric tag")
eq(Semver.parse(nil), nil, "parse rejects nil")
eq(Semver.parse(123), nil, "parse rejects a number")
eq(Semver.parse({}), nil, "parse rejects a table")

-- ---------------------------------------------------------------------------
-- Semver.compare
-- ---------------------------------------------------------------------------

-- ordering is major, then minor, then patch
eq(Semver.compare("2.0.0", "1.9.9"), 1, "compare: major dominates (a > b)")
eq(Semver.compare("1.0.0", "2.0.0"), -1, "compare: major dominates (a < b)")
eq(Semver.compare("1.2.0", "1.1.9"), 1, "compare: minor breaks a major tie (a > b)")
eq(Semver.compare("1.1.0", "1.2.0"), -1, "compare: minor breaks a major tie (a < b)")
eq(Semver.compare("1.1.2", "1.1.1"), 1, "compare: patch breaks a minor tie (a > b)")
eq(Semver.compare("1.1.1", "1.1.2"), -1, "compare: patch breaks a minor tie (a < b)")

-- equality
eq(Semver.compare("1.2.3", "1.2.3"), 0, "compare: identical versions are equal")
eq(Semver.compare("v1.2.3", "1.2.3"), 0, "compare: leading v does not change value")

-- string and already-parsed-table inputs interoperate on either side
eq(Semver.compare(Semver.parse("1.2.3"), "1.2.4"), -1, "compare: parsed-table a vs string b")
eq(Semver.compare("1.3.0", Semver.parse("1.2.9")), 1, "compare: string a vs parsed-table b")
eq(Semver.compare({ major = 2, minor = 0, patch = 0 },
                  { major = 1, minor = 9, patch = 9 }), 1, "compare: raw tables on both sides")
eq(Semver.compare(Semver.parse("4.4.4"), Semver.parse("4.4.4")), 0, "compare: equal parsed tables")

-- an unparseable side sorts as the lowest possible version, so a bogus value
-- never wins a "newer" test; two unparseable sides are equal
eq(Semver.compare("garbage", "1.0.0"), -1, "compare: unparseable a loses to a real version")
eq(Semver.compare("1.0.0", "garbage"), 1, "compare: a real version beats an unparseable b")
eq(Semver.compare("garbage", "junk"), 0, "compare: two unparseable sides are equal")
eq(Semver.compare(nil, "1.0.0"), -1, "compare: nil a sorts lowest")
eq(Semver.compare("1.0.0", nil), 1, "compare: nil b sorts lowest")

-- ---------------------------------------------------------------------------
-- Boot.select  (pure: no love.*)
-- ---------------------------------------------------------------------------

-- membership helper: toDelete order is deterministic, but assert on the set so
-- the tests document intent rather than iteration accidents
local function nameSet(list)
  local s = {}
  for _, n in ipairs(list) do s[n] = true end
  return s
end

-- empty candidate list: nothing to run, nothing to delete
do
  local chosen, del = Boot.select({}, "1.0.0", 1)
  eq(chosen, nil, "select: empty candidate list picks nothing")
  eq(#del, 0, "select: empty candidate list deletes nothing")
end

-- picks the highest eligible payload and marks the lower runnable ones (still
-- newer than bundled, but superseded by the winner) for deletion
do
  local candidates = {
    { name = "a.love", engine = "1.1.0" },            -- no minShell -> defaults to 1
    { name = "b.love", engine = "1.3.0", minShell = 1 },
    { name = "c.love", engine = "1.2.0", minShell = 1 },
  }
  local chosen, del = Boot.select(candidates, "1.0.0", 1)
  eq(chosen, "b.love", "select: picks the highest eligible engine")
  local d = nameSet(del)
  eq(#del, 2, "select: both losers are marked for deletion")
  check(d["a.love"] and d["c.love"], "select: superseded runnable payloads are deleted")
  check(not d["b.love"], "select: the chosen payload is never deleted")
end

-- skips payloads whose minShell is above the bundled shell, and KEEPS an
-- otherwise-newer one for a future shell upgrade instead of deleting it
do
  local candidates = {
    { name = "future.love", engine = "2.0.0", minShell = 2 }, -- unrunnable at shell 1
    { name = "ok.love",     engine = "1.5.0", minShell = 1 },
  }
  local chosen, del = Boot.select(candidates, "1.0.0", 1)
  eq(chosen, "ok.love", "select: skips a payload whose minShell exceeds the bundled shell")
  eq(#del, 0, "select: a newer-but-unrunnable payload is kept, not deleted")
  check(not nameSet(del)["future.love"], "select: unrunnable-newer payload survives")
end

-- skips payloads not strictly newer than bundled (older AND equal) and marks
-- them stale for deletion
do
  local candidates = {
    { name = "old.love",  engine = "0.9.0", minShell = 1 }, -- older than bundled
    { name = "same.love", engine = "1.0.0", minShell = 1 }, -- equal to bundled
    { name = "new.love",  engine = "1.1.0", minShell = 1 }, -- the only real update
  }
  local chosen, del = Boot.select(candidates, "1.0.0", 1)
  eq(chosen, "new.love", "select: only a strictly-newer payload is eligible")
  local d = nameSet(del)
  eq(#del, 2, "select: older and equal payloads are both stale")
  check(d["old.love"], "select: an older payload is deleted")
  check(d["same.love"], "select: a same-version payload is deleted")
  check(not d["new.love"], "select: the winner is not in the delete list")
end

-- no eligible payload at all (all older or equal): pick nothing, delete every
-- stale candidate
do
  local candidates = {
    { name = "old.love",  engine = "0.5.0", minShell = 1 },
    { name = "same.love", engine = "1.0.0", minShell = 1 },
  }
  local chosen, del = Boot.select(candidates, "1.0.0", 1)
  eq(chosen, nil, "select: no strictly-newer payload -> nothing chosen")
  eq(#del, 2, "select: every stale candidate is cleaned up when nothing wins")
end

-- the full mix in one pass: a superseded runnable one and a stale old one are
-- deleted; the chosen winner and a newer-but-unrunnable payload both survive
do
  local candidates = {
    { name = "sup.love",    engine = "1.2.0", minShell = 1 }, -- newer, runnable, < winner
    { name = "win.love",    engine = "1.4.0", minShell = 1 }, -- the winner
    { name = "future.love", engine = "2.0.0", minShell = 5 }, -- newer than winner, unrunnable
    { name = "old.love",    engine = "0.1.0", minShell = 1 }, -- stale
  }
  local chosen, del = Boot.select(candidates, "1.1.0", 1)
  eq(chosen, "win.love", "select(mix): highest runnable-newer engine wins")
  local d = nameSet(del)
  eq(#del, 2, "select(mix): exactly the superseded and stale payloads are deleted")
  check(d["sup.love"], "select(mix): a runnable payload below the winner is superseded")
  check(d["old.love"], "select(mix): a stale payload is cleaned up")
  check(not d["future.love"], "select(mix): a newer-but-unrunnable payload is kept")
  check(not d["win.love"], "select(mix): the winner is kept")
end

-- ---------------------------------------------------------------------------
-- Check.pickAsset
-- ---------------------------------------------------------------------------

local assets = {
  { name = "gen1recomp-1.4.2-macos.zip", browser_download_url = "http://x/mac", size = 10 },
  { name = "gen1recomp-1.4.2.love",      browser_download_url = "http://x/love", size = 12345 },
  { name = "sha256sums.txt",             browser_download_url = "http://x/sums", size = 99 },
}
local picked = Check.pickAsset(assets, "gen1recomp-1.4.2.love")
check(picked ~= nil, "pickAsset finds an asset by exact name")
eq(picked.url, "http://x/love", "pickAsset returns the download url")
eq(picked.size, 12345, "pickAsset returns the numeric size")
eq(Check.pickAsset(assets, "does-not-exist.love"), nil, "pickAsset misses cleanly on an unknown name")

-- coerces a string size to a number and tolerates non-table junk entries mixed
-- into the asset list
local coerced = Check.pickAsset({ "junk", 42, { name = "w", browser_download_url = "U", size = "7" } }, "w")
eq(coerced.size, 7, "pickAsset coerces a string size to a number")
eq(type(coerced.size), "number", "pickAsset size is a number after coercion")

-- guards a non-table / nil assets field instead of raising
eq(Check.pickAsset(nil, "x"), nil, "pickAsset tolerates a nil asset list")
eq(Check.pickAsset("nope", "x"), nil, "pickAsset tolerates a non-table asset list")

-- ---------------------------------------------------------------------------
-- Check.parseRelease  (release-JSON extraction)
-- ---------------------------------------------------------------------------

-- a well-formed release: version (leading v stripped), derived payload name,
-- and both the .love payload and its sums asset with url + size
local body = Json.encode({
  tag_name = "v1.4.2",
  assets = assets,
})
local rel = Check.parseRelease(body)
check(rel ~= nil, "parseRelease accepts a valid release")
eq(rel.version, "1.4.2", "parseRelease strips the leading v from tag_name")
eq(rel.payloadName, "gen1recomp-1.4.2.love", "parseRelease derives the payload name from the version")
eq(rel.payload.url, "http://x/love", "parseRelease picks the payload asset url")
eq(rel.payload.size, 12345, "parseRelease picks the payload asset size")
eq(rel.sums.url, "http://x/sums", "parseRelease picks the sums asset url")
eq(rel.sums.size, 99, "parseRelease picks the sums asset size")

-- a release with no .love yet still parses; payload/sums are nil so the worker
-- routes to a full reinstall rather than an in-place update
local noPayload = Check.parseRelease(Json.encode({ tag_name = "2.0.0", assets = {} }))
check(noPayload ~= nil, "parseRelease accepts a payload-less release")
eq(noPayload.version, "2.0.0", "parseRelease reads the version without any assets")
eq(noPayload.payload, nil, "parseRelease reports a missing payload asset as nil")
eq(noPayload.sums, nil, "parseRelease reports a missing sums asset as nil")

-- rejections carry an error string and never raise
local badTag, badTagErr = Check.parseRelease(Json.encode({ tag_name = "nightly" }))
eq(badTag, nil, "parseRelease rejects a non-X.Y.Z tag")
check(badTagErr ~= nil, "parseRelease rejection carries an error string")

local noTag, noTagErr = Check.parseRelease(Json.encode({ foo = 1 }))
eq(noTag, nil, "parseRelease rejects a document with no tag_name")
check(noTagErr ~= nil, "parseRelease missing-tag rejection carries an error string")

-- malformed input returns nil rather than raising (Json.decode yields nil, and
-- a bare non-object literal has no tag_name)
local ok1, garbage = pcall(Check.parseRelease, "this is not json {{{")
check(ok1, "parseRelease does not raise on unparseable JSON")
eq(garbage, nil, "parseRelease returns nil on unparseable JSON")
local ok2, empty = pcall(Check.parseRelease, "")
check(ok2, "parseRelease does not raise on empty input")
eq(empty, nil, "parseRelease returns nil on empty input")
local ok3, literal = pcall(Check.parseRelease, "42")
check(ok3, "parseRelease does not raise on a bare JSON literal")
eq(literal, nil, "parseRelease returns nil on a non-object JSON literal")

-- ---------------------------------------------------------------------------
-- Check.parseSums  (shasum -a 256 line parsing)
-- ---------------------------------------------------------------------------

-- standard "<hex>  <file>" lines, the '*' binary marker, a './' prefix, CRLF
-- endings and mixed hash case; junk lines are skipped
local sums =
  "aaaa1111  gen1recomp-1.4.2.love\n" ..
  "BBBB2222 *./sha256sums.txt\r\n" ..
  "deadBEEF  ./nested.love\n" ..
  "not a checksum line at all\n"
local map = Check.parseSums(sums)
eq(map["gen1recomp-1.4.2.love"], "aaaa1111", "parseSums reads a bare-name line")
eq(map["sha256sums.txt"], "bbbb2222", "parseSums strips the * marker and ./ prefix and lowercases")
eq(map["nested.love"], "deadbeef", "parseSums lowercases a mixed-case hash and strips ./")
eq(map["not a checksum line at all"], nil, "parseSums skips lines that are not checksums")

-- the target form returns just that file's hash (hit / miss)
eq(Check.parseSums(sums, "gen1recomp-1.4.2.love"), "aaaa1111", "parseSums(target) returns the matching hash")
eq(Check.parseSums(sums, "missing.love"), nil, "parseSums(target) misses cleanly on an unknown file")

-- degenerate inputs: empty text yields an empty map, a targeted miss is nil,
-- and a nil text does not raise
local emptyMap = Check.parseSums("")
eq(type(emptyMap), "table", "parseSums('') returns an (empty) table")
eq(next(emptyMap), nil, "parseSums('') has no entries")
eq(Check.parseSums(nil, "anything"), nil, "parseSums(nil, target) returns nil without raising")

-- ---------------------------------------------------------------------------
-- Check.releaseUrl  (the fixed public landing page)
-- ---------------------------------------------------------------------------

eq(Check.releaseUrl(),
   "https://github.com/bryanthaboi/gen1recomp/releases/latest",
   "releaseUrl points at the repo's latest release")

T.finish("update")
