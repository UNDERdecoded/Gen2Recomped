-- Pure coverage for src/mods/ModUpdate.lua (zip picking, release parse, isNewer).
--   luajit tests/engine/mod_update_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local ModUpdate = require("src.mods.ModUpdate")
local Json = require("src.link.Json")

do
  local assets = {
    { name = "readme.txt", browser_download_url = "https://x/r" },
    { name = "other-1.0.0.zip", browser_download_url = "https://x/o", size = 10 },
    { name = "coolmod-1.2.0.zip", browser_download_url = "https://x/c", size = 20 },
  }
  local pick = ModUpdate.pickZipAsset(assets, "coolmod", "1.2.0")
  eq(pick.name, "coolmod-1.2.0.zip", "prefers id-version.zip")
  eq(pick.url, "https://x/c", "returns the download URL")
end

do
  local assets = {
    { name = "payload.zip", browser_download_url = "https://x/p" },
  }
  local pick = ModUpdate.pickZipAsset(assets, "coolmod", "1.0.0")
  eq(pick.name, "payload.zip", "falls back to the first .zip")
end

do
  local body = Json.encode({
    {
      tag_name = "v1.2.0",
      name = "1.2.0",
      prerelease = false,
      assets = {
        { name = "demo-1.2.0.zip", browser_download_url = "https://x/d.zip",
          size = 99 },
      },
    },
    {
      tag_name = "v1.1.0",
      assets = {
        { name = "demo-1.1.0.zip", browser_download_url = "https://x/old.zip" },
      },
    },
    {
      tag_name = "notes-only",
      assets = {},
    },
  })
  local list = ModUpdate.parseReleases(body, "demo")
  eq(#list, 2, "releases without a zip are dropped")
  eq(list[1].version, "1.2.0", "keeps GitHub array order")
  eq(list[1].zip.url, "https://x/d.zip", "zip url is preserved")
end

check(ModUpdate.isNewer("1.0.0", "1.0.1"), "patch bump is newer")
check(not ModUpdate.isNewer("1.2.0", "1.1.9"), "older candidate is not newer")
check(not ModUpdate.isNewer("1.0.0", "1.0.0"), "same version is not newer")

eq(ModUpdate.apiLatestUrl("acme/mod"),
  "https://api.github.com/repos/acme/mod/releases/latest",
  "latest API URL")

-- soft-fail paths: garbage input must never throw
do
  local list, err = ModUpdate.parseReleases("{{{not json", "demo")
  check(list == nil and err ~= nil, "bad json returns nil, err")
  list, err = ModUpdate.parseReleases('{"message":"Not Found"}', "demo")
  check(list == nil and tostring(err):find("Not Found", 1, true),
    "GitHub error payload surfaces the message")
  list, err = ModUpdate.fetchReleases("", "demo")
  check(list == nil and err ~= nil, "empty repo soft-fails")
  local path, dlErr = ModUpdate.downloadZip("", "x.zip")
  check(path == nil and dlErr ~= nil, "empty url soft-fails")
end

do
  local body = Json.encode({
    tag_name = "v2.0.0",
    body = "## Changes\n\n- **fixed** the [thing](http://x)\n\n<!-- note -->",
    assets = {
      { name = "demo-2.0.0.zip", browser_download_url = "https://x/d.zip" },
    },
  })
  local list = ModUpdate.parseReleases(body, "demo")
  eq(list[1].body:sub(1, 2), "##", "release body is kept raw")
  local cleaned = ModUpdate.cleanBody(list[1].body, 200)
  check(cleaned:find("fixed", 1, true) and cleaned:find("thing", 1, true),
    "cleanBody keeps readable text")
  check(not cleaned:find("http://", 1, true), "cleanBody strips link urls")
  check(not cleaned:find("<!--", 1, true), "cleanBody strips HTML comments")

  local status, best = ModUpdate.statusFor("1.0.0", list)
  eq(status, "available", "newer release reports available")
  eq(best.version, "2.0.0", "best release is the newer one")
  eq(ModUpdate.statusFor("2.0.0", list), "current", "matching version is current")

  check(ModUpdate.cacheFresh({ checkedAt = os.time() - 10 }),
    "fresh cache is within TTL")
  check(not ModUpdate.cacheFresh({ checkedAt = os.time() - ModUpdate.CACHE_TTL - 1 }),
    "expired cache is not fresh")

  local preview = ModUpdate.previewLine(list[1].body, 40)
  check(not preview:find("\n", 1, true), "previewLine collapses newlines")
  check(#preview <= 41, "previewLine respects maxChars (+ellipsis)")
  check(preview:find("Changes", 1, true), "previewLine keeps heading text")
end

print("ok mod_update_tests")
