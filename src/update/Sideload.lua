-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A HAND-PLACED PAYLOAD, CHECKED BEFORE IT IS TRUSTED.
--
-- On the Switch and on Xbox the updater is notify-only: neither host can fetch
-- (io.popen cannot spawn and RAISES on Horizon and inside a UWP container,
-- love-nx exports no download bridge, the UWP LOVE backend in
-- ports/uwp/third_party/love ships as prebuilt binaries with no sources to add
-- one to, and LOVE's only socket library here is plain LuaSocket with no TLS
-- against an HTTPS-only GitHub).  What those hosts CAN do is host a payload:
-- src/update/Boot.lua mounts a .love out of the save directory over "/" and
-- chainloads it, and a file copied in by hand boots.  That copy is the whole
-- console update story outside the Switch's native OTA launcher.
--
-- IT WAS COMPLETELY UNVERIFIED.  Every other way a payload can arrive is
-- checked: src/update/check_worker.lua re-fetches the release manifest and
-- refuses a payload whose sha256 does not match before it ever lands, and
-- ports/switch/ota-launcher refuses a zip whose sum is missing or wrong
-- ("missing sum is ALWAYS reject").  The hand-placed path -- the ONE path the
-- two consoles actually have -- went straight into love.filesystem.mount.  A
-- truncated Device Portal upload, a half-written microSD copy or a file pulled
-- while the browser was still writing it mounts as the game: the archive
-- opens, src/core/Version.lua reads fine because it is near the front, and the
-- failure surfaces later as a missing module or a corrupt asset with nothing
-- pointing at the payload.
--
-- So: when the player drops the release's own sha256sums.txt into the payload
-- folder beside the payload, the shell verifies against it and refuses a
-- mismatch.  Opt-in by the presence of that file ON PURPOSE -- hashing 20 MB
-- at boot is work, the manifest is published with every release (measured on
-- v0.8.3: 1,171 bytes, and it lists the payload), and making it mandatory
-- would break the documented manual flow for every player who already uses it.
--
-- Four verdicts, and the sentence for each is here rather than in the caller so
-- "what the player is told" is gradeable without a love runtime:
--
--   verified    listed and the hash matches -> mount
--   mismatch    listed and the hash differs -> REFUSE, and say which is which
--   unlisted    a manifest is present but does not name this payload -> REFUSE
--   unverified  no manifest in the folder    -> mount, and say how to verify
--
-- "unlisted" refuses on purpose, matching the launcher's rule: a manifest the
-- player went to the trouble of placing, that does not cover the payload next
-- to it, means the two came from different releases, and that is exactly the
-- state a silent accept would hide.
--
-- Zero love.* calls and one require, so host tests and
-- tools/auto_update_check.lua drive every decision under plain Lua.

local Payload = require("src.update.Payload")

local Sideload = {}

Sideload.VERIFIED = "verified"
Sideload.MISMATCH = "mismatch"
Sideload.UNLISTED = "unlisted"
Sideload.UNVERIFIED = "unverified"

-- Every verdict, and whether the shell may mount on it.  A table rather than a
-- pair of if-chains so a fifth verdict cannot be added in one place and
-- forgotten in the other; tools/auto_update_check.lua walks it and asserts the
-- set it covers is exactly the set Boot.run branches on.
Sideload.VERDICTS = {
  [Sideload.VERIFIED] = { mount = true },
  [Sideload.MISMATCH] = { mount = false },
  [Sideload.UNLISTED] = { mount = false },
  [Sideload.UNVERIFIED] = { mount = true },
}

-- Sideload.verdict(name, sumsText, actualHex) -> verdict, expectedHex
--
-- sumsText nil (or not a string) is "no manifest present" and is the only
-- route to "unverified": an EMPTY manifest, or one that parses to nothing, is
-- a manifest that does not list this payload and refuses as "unlisted".  That
-- distinction is the one with teeth -- an empty file is far more likely to be
-- a failed copy of the manifest than a decision not to verify.
function Sideload.verdict(name, sumsText, actualHex)
  if type(sumsText) ~= "string" then
    return Sideload.UNVERIFIED, nil
  end
  local expected = Payload.parseSums(sumsText, tostring(name))
  if type(expected) ~= "string" or expected == "" then
    return Sideload.UNLISTED, nil
  end
  if type(actualHex) ~= "string" or actualHex == "" then
    return Sideload.MISMATCH, expected
  end
  if actualHex:lower() ~= expected:lower() then
    return Sideload.MISMATCH, expected
  end
  return Sideload.VERIFIED, expected
end

function Sideload.mayMount(verdict)
  local row = Sideload.VERDICTS[verdict]
  return (row and row.mount) and true or false
end

-- The one line the boot shell prints.  Loud for everything but "verified",
-- because the two silent cases are the two that used to be indistinguishable
-- from "auto-update does nothing": a payload refused for its hash, and a
-- payload trusted because nobody asked.
function Sideload.sentence(name, verdict, expectedHex, actualHex)
  name = tostring(name)
  if verdict == Sideload.VERIFIED then
    return ("sideload %s sha256 verified against %s"):format(name, Payload.SUMS)
  elseif verdict == Sideload.MISMATCH then
    return ("sideload %s REFUSED -- %s says %s, the file on disk is %s; the "
      .. "copy is corrupt or truncated, delete it and copy it across again")
      :format(name, Payload.SUMS, tostring(expectedHex):sub(1, 16),
        tostring(actualHex):sub(1, 16))
  elseif verdict == Sideload.UNLISTED then
    return ("sideload %s REFUSED -- a %s is present in %s/ but does not list "
      .. "this payload, so the two came from different releases")
      :format(name, Payload.SUMS, Payload.DIR)
  end
  return ("sideload %s is UNVERIFIED -- no %s in %s/; download that file from "
    .. "the same release and copy it in beside the payload to have this "
    .. "checked"):format(name, Payload.SUMS, Payload.DIR)
end

return Sideload
