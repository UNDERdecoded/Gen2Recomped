-- Pure-surface coverage for src/update/Check.lua (the self-update release
-- check / payload download module).  The network, hashing and archive-probe
-- logic lives in src/update/check_worker.lua and needs love + curl; these are
-- the love-free extraction/parsing seams the worker and UI both trust.
--   luajit tests/engine/update_check_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Check = require("src.update.Check")
local Json = require("src.link.Json")

-- releaseUrl is the fixed public landing page the UI links on needs_full
eq(Check.releaseUrl(),
   "https://github.com/bryanthaboi/gen1recomp/releases/latest",
   "releaseUrl points at the repo's latest release")

-- parseRelease: a well-formed release with the .love payload and its sums
local body = Json.encode({
  tag_name = "v1.4.2",
  assets = {
    { name = "gen1recomp-1.4.2-macos.zip", browser_download_url = "http://x/mac", size = 10 },
    { name = "gen1recomp-1.4.2.love", browser_download_url = "http://x/love", size = 12345 },
    { name = "sha256sums.txt", browser_download_url = "http://x/sums", size = 99 },
  },
})
local rel = Check.parseRelease(body)
check(rel ~= nil, "parseRelease accepts a valid release")
eq(rel.version, "1.4.2", "leading v stripped from tag_name")
eq(rel.payloadName, "gen1recomp-1.4.2.love", "payload name derived from version")
eq(rel.payload.url, "http://x/love", "payload asset url picked")
eq(rel.payload.size, 12345, "payload asset size picked")
eq(rel.sums.url, "http://x/sums", "sums asset url picked")

-- a newer release that ships no .love yet: parses, but the payload/sums are nil
-- so the worker will route to needs_full rather than an in-place update
local noPayload = Check.parseRelease(Json.encode({ tag_name = "2.0.0", assets = {} }))
check(noPayload ~= nil, "parseRelease accepts a payload-less release")
eq(noPayload.version, "2.0.0", "version parsed without assets")
eq(noPayload.payload, nil, "no payload asset -> nil")
eq(noPayload.sums, nil, "no sums asset -> nil")

-- rejects: non-semver tag, and a document with no tag at all
local bad, badErr = Check.parseRelease(Json.encode({ tag_name = "nightly" }))
eq(bad, nil, "non-X.Y.Z tag rejected")
check(badErr ~= nil, "rejection carries an error string")
eq(Check.parseRelease(Json.encode({ foo = 1 })), nil, "missing tag_name rejected")

-- parseSums: shasum -a 256 format, tolerating the '*' binary marker, a './'
-- prefix and CRLF line endings; unrelated lines are skipped
local sums =
  "aaaa1111  gen1recomp-1.4.2.love\n" ..
  "BBBB2222 *./sha256sums.txt\r\n" ..
  "not a checksum line\n"
local map = Check.parseSums(sums)
eq(map["gen1recomp-1.4.2.love"], "aaaa1111", "bare-name sum parsed")
eq(map["sha256sums.txt"], "bbbb2222", "* marker and ./ prefix stripped, lowered")
eq(Check.parseSums(sums, "gen1recomp-1.4.2.love"), "aaaa1111", "targeted lookup returns the hash")
eq(Check.parseSums(sums, "missing.love"), nil, "targeted lookup misses cleanly")

-- pickAsset guards a non-table assets field
eq(Check.pickAsset(nil, "x"), nil, "pickAsset tolerates a nil asset list")

T.finish("update_check")
