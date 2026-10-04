-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SELF-UPDATER, GRADED WHERE IT ACTUALLY BREAKS.
--
-- Three platforms sent the player to the GitHub releases page by hand, for
-- three different reasons, and not one of them printed anything:
--
--   Android   src/update/check_worker.lua posted `needs_full` for every
--             bridge-transport build, which is every Android build.  A POLICY
--             REFUSAL, not a failure -- so there was nothing to find in a log.
--   Switch    no HTTPS client reachable from Lua, so the check died at
--             "no network transport" with status "error" -- and the launcher
--             banner draws nothing for "error", so the player saw no updater.
--   Xbox      the same, plus a notify-only gate that could not fire: it keyed
--             on `_G.POKEPORT_NOTIFY_ONLY_UPDATES`, which occurs exactly once
--             in the repository (the read) and is set by nothing.
--
-- WHAT THIS GRADES, and each section is built so it can fail:
--
--   1. ONE FACT for where a payload lives.  The download destination and the
--      path Boot.run mounts were seven string literals in three files.  This
--      scans src/update with comments stripped and fails on a second spelling.
--   2. THE CAPABILITY RULE, driven with stub hosts.  io.popen is replaced for
--      the duration, so "the Switch must not reach io.popen at all" is an
--      assertion about a call that was counted, not a claim about a comment.
--   3. The semver comparison, including the measured pair that matters: the
--      working tree's 0.7.6 against the live release 0.8.3.
--   4. The sums parsing, in the format `sha256sum` emits and release.yml runs.
--   5. The minShell refusal -- `>` not `>=`, and a too-new payload KEPT.
--   6. That the state the notify-only leg posts is one the launcher banner
--      actually draws.  "Those builds CHECK and REPORT" was in a comment for
--      two years while the banner rendered nothing for the state they posted.
--
-- No cartridge and no cache: every assertion here runs on the tree alone.
--
-- Run:  texlua tools/auto_update_check.lua

package.path = "./?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local t = f:read("*a")
  f:close()
  return t
end

-- EVERY FILE THIS CHECK READS IS A COMMITTED REPO FILE, so "not present" is a
-- BROKEN TREE and not a missing optional input.
--
-- Four blocks here used to open with `if not read(path) then io.write("(... not
-- present -- skipped)") else ... end`, and that is the fault shape 5 of
-- claude/check_design_lessons.md names: without `ports/` the run lost **ten**
-- assertions, printed a parenthetical nobody greps for, and reported a plain
-- `PASS`.  The one assertion standing between the Switch's 404 and its return
-- vanished silently, and the suite line was indistinguishable from a full run.
--
-- AND `PASS*` WAS NEVER AVAILABLE FOR IT.  tools/run_checks.py sets that marker
-- at its own lines 255-259 from `reduced`, which it populates at line 247 only
-- when an OPTIONAL ARGUMENT SLOT declared in a check's `Run:` line was not
-- supplied.  It never reads the check's output, and this check declares no
-- argument slots at all, so `reduced` is permanently empty here.  A check
-- cannot ask to be marked reduced; it can only fail.
--
-- So: fail, naming the path.  `git ls-files` confirms all four are tracked and
-- `git check-ignore` that none is ignored, which is what makes absence a fault
-- rather than a condition.  The dependent block is then skipped so the run
-- produces ONE diagnosable failure instead of ten cascades against nil.
local function required(path, why)
  local text = read(path)
  ok(text ~= nil,
     "%s is MISSING FROM THE TREE. It is a committed file, so this is a broken "
     .. "checkout rather than an absent optional input -- and %s",
     path, why)
  return text
end

-- Cut every Lua comment, so a literal quoted inside an explanation of why it
-- is no longer used does not read as a second spelling of it.  Quote-aware:
-- a "--" inside a string is not a comment, and the long-bracket forms are
-- handled because this tree uses [[ ]] for embedded shell/ffi text.
local function stripComments(src)
  local out, i, n = {}, 1, #src
  local quote = nil
  while i <= n do
    local c = src:sub(i, i)
    if quote then
      if c == "\\" and quote ~= "]]" then
        out[#out + 1] = src:sub(i, i + 1); i = i + 2
      elseif quote == "]]" and src:sub(i, i + 1) == "]]" then
        out[#out + 1] = "]]"; i = i + 2; quote = nil
      elseif c == quote and quote ~= "]]" then
        out[#out + 1] = c; i = i + 1; quote = nil
      else
        out[#out + 1] = c; i = i + 1
      end
    elseif src:sub(i, i + 3) == "--[[" then
      local close = src:find("]]", i + 4, true)
      i = close and (close + 2) or (n + 1)
    elseif src:sub(i, i + 1) == "--" then
      local nl = src:find("\n", i, true)
      i = nl or (n + 1)
    elseif src:sub(i, i + 1) == "[[" then
      out[#out + 1] = "[["; i = i + 2; quote = "]]"
    elseif c == '"' or c == "'" then
      out[#out + 1] = c; i = i + 1; quote = c
    else
      out[#out + 1] = c; i = i + 1
    end
  end
  return table.concat(out)
end

local UPDATE_FILES = { "Boot.lua", "Check.lua", "check_worker.lua", "Semver.lua" }

-- The statuses the launcher banner actually renders, read off the launcher.
-- src/import/RomImporter.lua is READ here and never written.  Nil when the
-- launcher is not in the tree, which is the only reason the checks that use it
-- are conditional.
--
-- ONLY the `upStatus == "..."` comparisons.  The first draft of this swept in
-- every `status == "..."` in the file and therefore collected "error",
-- "conflict", "current" and "ok" -- which belong to the mod-update and
-- save-conflict rows, not to the updater banner.  With "error" in the set the
-- assertion below could not fail, and a planted fault that made the refusal
-- leave status "error" passed: a measurement that cannot fail says nothing.
-- `upStatus` is the banner's own local and is not used by anything else.
--
-- AND IT MUST READ THE DISPATCH HEADS, not every mention.  A planted fault
-- removed `or upStatus == "notify"` from the banner's branch head and this
-- still reported notify as drawn, because a *second* test of the same literal
-- lived inside the branch body.  The state was no longer rendered and the
-- membership assertion passed: a vocabulary scan with two sources for one
-- token grades neither.  The launcher now resolves that inner case into a
-- boolean before the dispatch, and this anchors on the `if` / `elseif` at the
-- dispatch's own indent so a re-introduced inner test cannot feed it either.
local function bannerStatuses()
  local ui = read("src/import/RomImporter.lua")
  if not ui then return nil end
  local drawn = {}
  for _, lead in ipairs({ "\n    if ", "\n    elseif " }) do
    for head in ui:gmatch(lead .. "([^\r\n]-) then") do
      if head:find("upStatus", 1, true) then
        for status in head:gmatch('upStatus == "([%a_]+)"') do drawn[status] = true end
      end
    end
  end
  if next(drawn) == nil then return nil end
  return drawn
end
local BANNER = bannerStatuses()

-- The advice values the launcher's banner actually branches on, read the same
-- way and from the same local.  Independent of Check.ADVICE on purpose: the two
-- are compared below, so a fifth advice added in Check and ignored in the
-- launcher fails rather than silently drawing the default sentence.
local function bannerAdvices()
  local ui = read("src/import/RomImporter.lua")
  if not ui then return nil end
  local seen = {}
  for a in ui:gmatch('upAdvice == "([%a_]+)"') do seen[a] = true end
  if next(seen) == nil then return nil end
  return seen
end
local BANNER_ADVICE = bannerAdvices()

-- ---------------------------------------------------------------------------
section("1. one fact for where a payload lives")
-- ---------------------------------------------------------------------------

local okP, Payload = pcall(require, "src.update.Payload")
ok(okP and type(Payload) == "table",
   "src/update/Payload.lua did not load: %s", tostring(Payload))
if not (okP and type(Payload) == "table") then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

ok(Payload.name("0.8.3") == "Gen2Recomped-0.8.3.love",
   "Payload.name(\"0.8.3\") is %q, but the release asset .github/workflows/"
   .. "release.yml stages is Gen2Recomped-0.8.3.love and sha256sums.txt "
   .. "lists it under that name -- the checksum lookup is by this string",
   tostring(Payload.name("0.8.3")))

-- The agreement that was two facts: the file the transport writes and the file
-- Boot.run enumerates.  Derived from the module both now ask, so a change to
-- DIR or PREFIX that only lands on one side cannot pass.
do
  local rel = Payload.rel("1.2.3")
  local dir, base = rel:match("^(.+)/([^/]+)$")
  ok(dir == Payload.DIR,
     "Payload.rel() writes into %q but Boot.run enumerates %q -- the "
     .. "downloaded payload would land where the boot shell does not look",
     tostring(dir), tostring(Payload.DIR))
  ok(base ~= nil and Payload.isName(base),
     "Boot.run's isPayloadName rejects %q, the very name Payload.rel() "
     .. "produces: a verified download would be skipped at the next boot",
     tostring(base))
  ok(not Payload.isName(Payload.partRel("1.2.3"):match("[^/]+$")),
     "Payload.isName accepts the in-flight .part name, so Boot.run would "
     .. "probe a half-downloaded archive as a candidate")
  ok(not Payload.isName(Payload.doneRel("1.2.3"):match("[^/]+$")),
     "Payload.isName accepts the .done marker as a payload")
  ok(not Payload.isName("pending.txt") and not Payload.isName("dl.bat"),
     "Payload.isName accepts a non-payload file in %s/", Payload.DIR)
  ok(Payload.PENDING:match("^" .. Payload.DIR .. "/") ~= nil,
     "the crash-guard marker %q is not inside %s/, so Boot's pending check "
     .. "and its payload folder have parted company",
     Payload.PENDING, Payload.DIR)
end

-- Nobody else may spell it.  This is the assertion that fails if the next pass
-- hardcodes "updates/..." in a new transport branch.
do
  local offenders = {}
  for _, name in ipairs(UPDATE_FILES) do
    local src = read("src/update/" .. name)
    ok(src ~= nil, "src/update/%s could not be read", name)
    if src then
      local code = stripComments(src)
      if code:find('"' .. Payload.DIR, 1, true) then
        offenders[#offenders + 1] = name .. ' spells "' .. Payload.DIR .. '..."'
      end
      -- The payload EXTENSION in a string literal is the giveaway for a
      -- hand-built asset name; the prefix alone also appears as a User-Agent.
      if code:find(Payload.EXT .. '"', 1, true) then
        offenders[#offenders + 1] = name .. ' builds a name ending ' .. Payload.EXT
      end
    end
  end
  if #offenders > 0 then
    for _, o in ipairs(offenders) do io.write("   ", o, "\n") end
  end
  ok(#offenders == 0,
     "%d file(s) in src/update still build the payload path themselves "
     .. "instead of asking src/update/Payload.lua -- that is the fault this "
     .. "module exists to stop", #offenders)
end

-- The repository slug, once.  check_worker.lua used to name it a second time
-- in its API URL, so moving the repo moved the "Open releases" button and left
-- the API call pointing at the old one.
do
  local Check = require("src.update.Check")
  ok(type(Check.REPO) == "string" and Check.REPO:match("^[%w%-%.]+/[%w%-%.]+$"),
     "Check.REPO is not an owner/name slug: %q", tostring(Check.REPO))
  local worker = stripComments(read("src/update/check_worker.lua") or "")
  ok(not worker:find(Check.REPO, 1, true),
     "src/update/check_worker.lua names the repository (%s) a second time "
     .. "instead of deriving its API URL from Check.REPO", Check.REPO)
  ok(worker:find("Check.REPO", 1, true) ~= nil,
     "src/update/check_worker.lua no longer derives its API URL from "
     .. "Check.REPO, so the releases page and the API can drift apart")

  -- THE CROSS-LANGUAGE HALF, and it was wrong.  The Switch's native OTA
  -- launcher is the Switch's whole update path, and it carried the slug in C:
  --
  --   ports/switch/ota-launcher/include/ota_protocol.h
  --     #define OTA_RELEASES_API
  --       "https://api.github.com/repos/UNDERdecodedHD/Gen2Recomped/..."
  --   ports/switch/ota-launcher/src/main.c
  --       "https://github.com/UNDERdecodedHD/Gen2Recomped/releases/download/..."
  --
  -- Measured 2026-10-04: that slug answers HTTP 404 and the one in Check.REPO
  -- answers 200.  So the launcher 404ed on every boot, concluded "up to date
  -- or offline", and showed nothing -- while Check.lua's own comment described
  -- this exact mistake, in this exact repository, two directories away.
  --
  -- "UNDERdecodedHD" is the AUTHOR name (NACP author, MSIX publisher, the
  -- intro credit) and is correct wherever it appears as a name; the GitHub
  -- owner is "UNDERdecoded".  So this asserts the slug, not the absence of the
  -- string.
  do
    local header = required("ports/switch/ota-launcher/include/ota_protocol.h",
      "it carries OTA_REPO_SLUG, which is the only thing in the tree standing "
      .. "between the Switch OTA launcher's 404 and its return")
    if header then
      local slug = header:match('#define%s+OTA_REPO_SLUG%s+"([^"]+)"')
      ok(slug ~= nil,
         "ota_protocol.h defines no OTA_REPO_SLUG, so the Switch OTA "
         .. "launcher is spelling the repository out per URL again")
      ok(slug == Check.REPO,
         "the Switch OTA launcher asks %q and src/update/Check.lua asks %q. "
         .. "One of them is pointing at a repository that does not exist, and "
         .. "a 404 reaches that launcher as \"up to date or offline\" -- it "
         .. "shows nothing and the console silently stops updating",
         tostring(slug), tostring(Check.REPO))
      -- Both URLs must come from it, or the next edit re-splits them.
      -- Read as a window after the macro name rather than with a pattern that
      -- has to model the line continuation: a two-line #define is exactly the
      -- shape shape 3a warns about.
      for _, macro in ipairs({ "OTA_RELEASES_API", "OTA_SUMS_URL_FMT" }) do
        local at = header:find("#define " .. macro, 1, true)
        ok(at ~= nil, "ota_protocol.h no longer defines %s", macro)
        local window = at and header:sub(at, at + 200) or ""
        ok(window:find("OTA_REPO_SLUG", 1, true) ~= nil,
           "%s does not build its URL from OTA_REPO_SLUG, so the owner is "
           .. "spelled out again and can drift from Check.REPO", macro)
      end
      local mainc = read("ports/switch/ota-launcher/src/main.c")
      ok(mainc == nil or mainc:find("github.com/UNDER", 1, true) == nil,
         "ports/switch/ota-launcher/src/main.c writes a github.com URL with "
         .. "the owner spelled out, instead of using OTA_SUMS_URL_FMT")
      -- And the dangling reference: a comment in the header and a line in the
      -- README both pointed at src/update/SwitchOta.lua, which has never
      -- existed in this tree.
      -- The dead POINTER, written as a path -- not the bare name, so that
      -- prose explaining the removal is not mistaken for the reference.  The
      -- path is also how the original was written, which is what a revert
      -- would restore.
      local DEAD = "src/update/SwitchOta.lua"
      ok(header:find(DEAD, 1, true) == nil,
         "ota_protocol.h points at %s, which has never existed in this tree",
         DEAD)
      local readme = read("ports/switch/ota-launcher/README.md")
      ok(readme == nil or readme:find(DEAD, 1, true) == nil,
         "ports/switch/ota-launcher/README.md points at %s, which has never "
         .. "existed in this tree", DEAD)
      ok(readme == nil or readme:find("ota_protocol", 1, true) ~= nil,
         "the README no longer names the file the wire format actually lives "
         .. "in, so the reference it replaced has nowhere to point")
    end
  end
end

-- The asset name, checked against the line that PRODUCES it rather than
-- against this file's opinion of it.
do
  local wf = required(".github/workflows/release.yml",
    "it is the line that names the release asset, and without it this check "
    .. "only compares src/update/Payload.lua against itself")
  if wf then
    local want = Payload.PREFIX .. "${v}" .. Payload.EXT
    ok(wf:find(want, 1, true) ~= nil,
       "release.yml does not stage an asset named %q, so every release would "
       .. "look to Check.parseRelease like one with no payload (needs_full)",
       want)
    ok(wf:find("sha256sums.txt", 1, true) ~= nil,
       "release.yml does not produce sha256sums.txt, which the download "
       .. "verification reads -- every download would fail its checksum")
  end
end

-- A DOC THAT CONTRADICTS THE DOC BESIDE IT is this project's favourite way to
-- lose a fact.  docs/updater.md described the mechanism and carried the OLD
-- payload spelling (`gen1recomp-X.Y.Z.love`, from the Gen 1 port this forked
-- from) plus a "Known limitations" bullet saying Android had no in-app download
-- transport -- which had been false for a release and a half.  Both are cheap
-- to hold still: the payload name is derived here, and the bullet's claim is
-- asserted absent.
do
  local doc = required("docs/updater.md",
    "it is the mechanism doc, and the four claims asserted here are the ones "
    .. "that had already gone stale once")
  if doc then
    ok(doc:find("gen1recomp-", 1, true) == nil,
       "docs/updater.md still spells the payload gen1recomp-X.Y.Z.love, the "
       .. "Gen 1 port's name -- a reader following it would look for an asset "
       .. "no release has carried since the fork")
    ok(doc:find(Payload.PREFIX .. "X.Y.Z" .. Payload.EXT, 1, true) ~= nil,
       "docs/updater.md does not name %s, so the mechanism doc and "
       .. "src/update/Payload.lua disagree about the asset",
       Payload.PREFIX .. "X.Y.Z" .. Payload.EXT)
    ok(doc:find("Android has no in-app download transport", 1, true) == nil,
       "docs/updater.md still claims Android has no in-app download "
       .. "transport; it has had the JNI bridge since #597 and now uses it to "
       .. "fetch payloads")
    ok(doc:find("auto%-update%.md") ~= nil,
       "docs/updater.md does not point at docs/auto-update.md, so a reader "
       .. "asking \"why doesn't my platform update\" lands on the mechanism "
       .. "doc and stops there")
  end
end

-- ---------------------------------------------------------------------------
section("2. the capability rule, driven with stub hosts")
-- ---------------------------------------------------------------------------

local realPopen = io.popen
local popenCalls = 0

-- An in-memory love.filesystem.  `writable` false makes write() RETURN false,
-- which is what physfs does on a read-only mount -- not raise, which is the
-- case the probe would miss if it only pcalled.
local function fakeFs(writable, fused, saveDir)
  local store = {}
  return {
    write = function(path, data)
      if not writable then return false, "read-only" end
      store[path] = data; return true
    end,
    read = function(path) return store[path] end,
    remove = function(path) store[path] = nil; return true end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return saveDir or "/stub/save" end,
    mount = function() return true end,
    unmount = function() return true end,
    isFused = function() return fused and true or false end,
    getDirectoryItems = function() return {} end,
    getInfo = function() return nil end,
  }
end

local function stubHost(osName, opts)
  opts = opts or {}
  popenCalls = 0
  io.popen = function(cmd, mode)
    popenCalls = popenCalls + 1
    if not opts.curl then return nil end
    return {
      read = function() return "curl 8.5.0 (x86_64) libcurl/8.5.0" end,
      close = function() return true end,
      lines = function() return function() return nil end end,
    }
  end
  _G.love = {
    _os = osName,
    system = {
      getOS = function() return osName end,
      httpDownload = opts.bridge and function() return true end or nil,
      openURL = function() return true end,
    },
    filesystem = fakeFs(opts.writable ~= false, opts.fused ~= false,
      opts.saveDir),
    data = { hash = function() return "" end,
             encode = function() return "" end },
  }
  _G.POKEPORT_NOTIFY_ONLY_UPDATES = opts.suppress or nil
  require("src.core.Platform")._resetForTests()
  require("src.update.Check")._resetCapabilityForTests()
end

local Check = require("src.update.Check")
local Platform = require("src.core.Platform")
local HostShell = require("src.core.HostShell")

-- Capture the announcement so the "three-way branch must say which leg it
-- took" rule is graded rather than hoped for.
local said = {}
local realPrint = print
_G.print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  said[#said + 1] = table.concat(parts, "\t")
end

local CASES = {
  -- name,          OS,        opts,                               mode
  { "desktop Linux with curl", "Linux",   { curl = true },          "self-update" },
  { "desktop macOS with curl", "OS X",    { curl = true },          "self-update" },
  { "desktop Windows, no curl", "Windows", { curl = false },        "notify-only" },
  { "Android (JNI bridge)",    "Android", { bridge = true },        "self-update" },
  { "Switch (NX)",             "NX",      {},                       "notify-only" },
  { "Xbox UWP",                "UWP",     {},                       "notify-only" },
  -- A UWP container that reports "Windows" -- which is what the old OS table
  -- could not tell apart from a desktop, and the reason it never fired.
  { "UWP reporting Windows",   "Windows", {},                       "notify-only" },
  { "read-only save directory", "Linux",  { curl = true, writable = false },
                                                                     "unavailable" },
  { "source checkout (unfused)", "Linux", { curl = true, fused = false },
                                                                     "notify-only" },
  { "explicitly suppressed",   "Linux",   { curl = true, suppress = true },
                                                                     "suppressed" },
}

-- WHAT THE PLAYER IS TOLD TO DO, per host.  The wording lives in the launcher;
-- this grades the decision, which lives in Check.capability.  Driven through
-- real save-directory shapes, because telling a UWP container apart from a
-- desktop Windows build is the thing Check.lua spent two years asserting was
-- impossible -- and it is, from love._os.  It is not from the writable folder
-- the OS hands a process with package identity.
local ADVICE_CASES = {
  { "desktop Linux with curl", "Linux", { curl = true },
    "C:/stub/save", "download" },
  { "Android", "Android", { bridge = true }, "/stub/save", "download" },
  { "Switch", "NX", {}, "sdmc:/switch/gen2recomp/pokemon-love2d", "ota" },
  -- The real UWP/MSIX shape: SDL_GetPrefPath under WinRT hands out the
  -- package's own local folder, and the `Packages` component is there because
  -- the process has package identity.
  { "Xbox UWP container reporting Windows", "Windows", {},
    "C:\\Users\\p\\AppData\\Local\\Packages\\Gen2RecompedUWP_8w\\LocalState\\Gen2Recomp",
    "package" },
  { "MSIX desktop install, no curl", "Windows", {},
    "C:\\Users\\p\\AppData\\Local\\Packages\\Gen2Recomped_8w\\LocalCache\\Roaming\\LOVE\\Gen2Recomp",
    "package" },
  -- A plain desktop Windows build with no curl is the case that MUST NOT be
  -- read as a container: it has a browser, so the releases page is the right
  -- advice and the button is worth drawing.
  { "desktop Windows, no curl", "Windows", {},
    "C:\\Users\\p\\AppData\\Roaming\\LOVE\\Gen2Recomp", "releases" },
  { "desktop Linux, no curl", "Linux", {},
    "/home/p/.local/share/love/Gen2Recomp", "releases" },
}

for _, case in ipairs(CASES) do
  local name, osName, opts, want = case[1], case[2], case[3], case[4]
  said = {}
  stubHost(osName, opts)
  local okCap, cap = pcall(Check.capability)
  ok(okCap and type(cap) == "table",
     "%s: Check.capability() raised: %s", name, tostring(cap))
  if okCap and type(cap) == "table" then
    ok(cap.mode == want,
       "%s: capability mode is %q, expected %q (host=%s transport=%s "
       .. "host-payload=%s fused=%s)",
       name, tostring(cap.mode), want, tostring(cap.host),
       tostring(cap.transport), tostring(cap.canHostPayload),
       tostring(cap.fused))
    ok(cap.mode == "self-update" or (type(cap.reason) == "string" and cap.reason ~= ""),
       "%s: refused with mode %q and no reason -- a silent refusal is the "
       .. "bug, not the fix", name, tostring(cap.mode))
    ok(Check.canSelfUpdate() == (want == "self-update"),
       "%s: canSelfUpdate() disagrees with capability mode %q",
       name, tostring(cap.mode))
    ok(Check.notifyOnly() == (want == "notify-only" or want == "suppressed"),
       "%s: notifyOnly() disagrees with capability mode %q",
       name, tostring(cap.mode))
    local announced = false
    for _, line in ipairs(said) do
      if line:find("update: capability", 1, true) then announced = true end
    end
    ok(announced, "%s: took the %q branch without logging which branch it "
       .. "took -- that is what made this bug invisible", name, want)
    -- WHAT THE PLAYER IS LEFT LOOKING AT when the Update button is tapped on
    -- a host that cannot fetch.  The banner renders four of the eight states
    -- and nothing for the other four, so a refusal that leaves "error" or
    -- "idle" behind is the Switch/Xbox bug again: a button that does nothing
    -- visible.  This is why the refusal now sits ahead of the worker guard --
    -- behind it, on a host with no worker, it never ran at all.
    if want ~= "self-update" and BANNER then
      pcall(Check.download)
      local st = Check.state()
      ok(BANNER[st.status] == true,
         "%s: refusing the download left status %q, which the launcher banner "
         .. "does not draw -- the player taps Update and sees nothing change",
         name, tostring(st.status))
    end
  end
end

for _, case in ipairs(ADVICE_CASES) do
  local name, osName, opts, saveDir, want = case[1], case[2], case[3], case[4], case[5]
  opts.saveDir = saveDir
  stubHost(osName, opts)
  local got = Check.advice()
  ok(got == want,
     "%s: advice is %q, expected %q (save directory %q)",
     name, tostring(got), want, saveDir)
  ok(Check.ADVICE[got] == true,
     "%s: advice %q is not in Check.ADVICE, so the launcher's join assertion "
     .. "cannot cover it", name, tostring(got))
end

-- And the measurement the two container cases rest on, on its own, both ways.
do
  stubHost("Windows", { saveDir =
    "C:\\Users\\p\\AppData\\Local\\Packages\\Gen2RecompedUWP_8w\\LocalState\\Gen2Recomp" })
  ok(Platform.isPackagedContainer() == true,
     "a packaged container's save directory was not recognised, so Xbox falls "
     .. "back to the desktop wording -- the exact failure the old OS table had")
  stubHost("Windows", { saveDir = "C:\\Users\\p\\AppData\\Roaming\\LOVE\\Gen2Recomp" })
  ok(Platform.isPackagedContainer() == false,
     "a desktop Windows save directory was read as a packaged container, so a "
     .. "desktop build would be told to install a newer package")
  stubHost("Linux", { saveDir = "/home/p/.local/share/love/Gen2Recomp" })
  ok(Platform.isPackagedContainer() == false,
     "a Linux save directory was read as a packaged container")
end

-- THE SWITCH/UWP RAISE.  io.popen does not return nil on those hosts, it
-- raises from inside the call, so the only safe answer is not to call it.  The
-- counter makes that an observation.
for _, osName in ipairs({ "NX", "UWP", "Android", "iOS" }) do
  stubHost(osName, {})
  pcall(Check.capability)
  ok(popenCalls == 0,
     "%s: io.popen was called %d time(s) while resolving the transport -- on "
     .. "the Switch and in a UWP container that call RAISES "
     .. "(\"'popen' not supported\") rather than returning nil",
     osName, popenCalls)
  ok(HostShell.canSpawnProcess() == false,
     "%s: HostShell.canSpawnProcess() is true", osName)
end

for _, osName in ipairs({ "Linux", "OS X", "Windows" }) do
  stubHost(osName, { curl = true })
  pcall(Check.capability)
  ok(popenCalls > 0,
     "%s: the transport was resolved without ever probing for curl, so a "
     .. "desktop with no curl would be reported as able to self-update",
     osName)
  ok(Platform.canSpawnProcess() == true,
     "%s: Platform.canSpawnProcess() is false -- it must agree with "
     .. "HostShell, which now owns the one definition", osName)
end

-- Android must resolve the bridge, and a desktop must prefer curl, so the
-- updater and the mod index cannot disagree about what the transport is.
stubHost("Android", { bridge = true })
do
  local kind = HostShell.transport()
  ok(kind == "bridge", "Android resolved transport %q, not \"bridge\"",
     tostring(kind))
  ok(HostShell.canFetch() == true, "Android reports no transport at all")
  ok(Platform.canHostPayload() == true,
     "Android cannot host a payload, yet its save directory took the probe")
end
stubHost("NX", {})
do
  local kind, why = HostShell.transport()
  ok(kind == nil, "NX resolved transport %q", tostring(kind))
  ok(type(why) == "string" and why ~= "",
     "NX has no transport and no sentence saying why")
  ok(Platform.canHostPayload() == true,
     "NX reports it cannot host a payload.  Boot.run mounts a .love out of "
     .. "the SAVE DIRECTORY, which is writable on the Switch -- a payload "
     .. "copied there by hand runs, and this is what refusing it costs")
end

-- ---------------------------------------------------------------------------
-- The deferred bridge transfer, driven for real.
-- ---------------------------------------------------------------------------
--
-- The payload is 20,368,165 bytes (measured off v0.8.3's release asset) and
-- the bridge blocks the thread it is called on for the whole transfer.  That
-- thread is the one LOVE drives the frame loop on, so whatever was last drawn
-- is what the player stares at.  So a request marked `big` must be answered
-- one drain LATE: the first drain posts the downloading state and returns, a
-- frame draws the banner, and the NEXT drain runs the transfer.
--
-- Graded by counting transfers per drain, with in-memory channels and a stub
-- bridge -- not by reading the comment that says so.
do
  stubHost("Android", { bridge = true })
  local channels, downloads = {}, {}
  local function channel(name)
    if not channels[name] then
      local q = {}
      channels[name] = {
        push = function(_, v) q[#q + 1] = v end,
        pop = function() return table.remove(q, 1) end,
        clear = function() for i = #q, 1, -1 do q[i] = nil end end,
        demand = function() return table.remove(q, 1) end,
        count = function() return #q end,
      }
    end
    return channels[name]
  end
  _G.love.thread = {
    getChannel = channel,
    newThread = function()
      return { start = function() end, getError = function() return nil end,
               wait = function() end }
    end,
  }
  _G.love.system.httpDownload = function(url, absPath)
    downloads[#downloads + 1] = absPath
    return true
  end

  Check.start()
  ok(Check.state().status == "checking",
     "Check.start() did not reach \"checking\" with a worker available (%s)",
     tostring(Check.state().status))

  channel("update_bridge_req"):push({
    seq = 1, url = "https://example.invalid/payload", dest = "updates/p.love",
    big = true, version = "9.9.9", size = 20368165,
  })

  local st = Check.state()           -- drain 1: defer
  ok(#downloads == 0,
     "the big bridge transfer ran on the SAME drain that first saw it: the "
     .. "launcher blocks for the whole transfer with the pre-download frame "
     .. "still on screen (%d transfer(s) already)", #downloads)
  ok(st.status == "downloading",
     "the deferred frame did not report \"downloading\" (%s), so the player "
     .. "has nothing on screen while the transfer blocks", tostring(st.status))
  ok(channel("update_bridge_res"):count() == 0,
     "a result was pushed before the transfer ran, so the worker would carry "
     .. "on as though the payload had arrived")

  Check.state()                      -- drain 2: transfer
  ok(#downloads == 1,
     "the deferred big transfer never ran on the following drain (%d "
     .. "transfer(s)); the worker waits on the reply channel forever and the "
     .. "download times out", #downloads)
  ok(type(downloads[1]) == "string" and downloads[1]:find("updates/p.love", 1, true),
     "the bridge was handed %q, not the save-directory-absolute path of the "
     .. "requested destination -- a save-dir-RELATIVE path handed to the JNI "
     .. "bridge is one of the three things that used to abort the process",
     tostring(downloads[1]))
  ok(downloads[1]:sub(1, 1) == "/" or downloads[1]:match("^%a:"),
     "the bridge was handed a relative path (%q)", tostring(downloads[1]))
  ok(channel("update_bridge_res"):count() == 1,
     "the transfer ran and no result was pushed, so the worker stays blocked")

  Check.shutdown()
end

-- ---------------------------------------------------------------------------
-- A host with no transport must not start a worker, and must say why.
-- ---------------------------------------------------------------------------
--
-- The Switch and an Xbox UWP container have no HTTPS client reachable from
-- Lua, so the worker could only time out against a network it cannot use, and
-- the "error" state it ends on is one the launcher banner does not draw.  That
-- combination is what produced NO DIAGNOSTIC AT ALL on those two platforms for
-- two years, while a comment above the gate claimed they "CHECK and REPORT".
do
  for _, osName in ipairs({ "NX", "UWP" }) do
    stubHost(osName, {})
    local threads = 0
    _G.love.thread = {
      getChannel = function()
        local q = {}
        return { push = function(_, v) q[#q + 1] = v end,
                 pop = function() return table.remove(q, 1) end,
                 clear = function() end,
                 demand = function() return nil end }
      end,
      newThread = function()
        threads = threads + 1
        return { start = function() end, getError = function() return nil end,
                 wait = function() end }
      end,
    }
    said = {}
    Check.start()
    ok(threads == 0,
       "%s: Check.start() spun up %d background worker(s) on a host with no "
       .. "transport; it can only time out, and the state it ends on is one "
       .. "the launcher banner does not draw", osName, threads)
    local st = Check.state()
    -- Not merely "it left a state": it must leave one the banner DRAWS, with a
    -- reason attached.  This leg used to end on "error", which Check.STATUS
    -- marks undrawable, so the Switch and Xbox showed the player nothing.
    ok(st.status == "notify" and type(st.error) == "string" and st.error ~= "",
       "%s: Check.start() left status %q with error %q -- a host that cannot "
       .. "check must leave a drawable state with a reason, not fall silent",
       osName, tostring(st.status), tostring(st.error))
    ok(Check.STATUS[st.status] == true,
       "%s: Check.start() left status %q, which Check.STATUS does not mark "
       .. "drawable -- the launcher banner renders nothing for it",
       osName, tostring(st.status))
    ok(BANNER == nil or BANNER[st.status] == true,
       "%s: Check.start() left status %q and the launcher banner has no branch "
       .. "for it", osName, tostring(st.status))
    local named = false
    for _, line in ipairs(said) do
      if line:find("update: capability", 1, true) then named = true end
    end
    ok(named,
       "%s: a fused launcher run produced no capability line at all.  "
       .. "Check.capability() used to be asked only by Check.download, which "
       .. "on a host that never draws an Update button is never called",
       osName)
  end
end

_G.print = realPrint
io.popen = realPopen
_G.love = nil
_G.POKEPORT_NOTIFY_ONLY_UPDATES = nil

-- THE ANDROID REFUSAL, read off the worker.  Check.capability() cannot see it:
-- the refusal was in the worker's own doCheck, which this file cannot load
-- (its last statement is a blocking command loop), so the two shapes are
-- asserted against its text.  A build that can fetch must have somewhere to
-- fetch TO, and must not decline on the ground that the transport is the
-- bridge -- that single branch was every Android release's update path.
do
  local worker = stripComments(read("src/update/check_worker.lua") or "")
  ok(worker:find('how == "bridge"', 1, true) ~= nil,
     "src/update/check_worker.lua's doDownload has no bridge branch, so "
     .. "Android can learn a release exists and has no way to fetch it")
  ok(worker:find('resolveTransport() == "bridge"', 1, true) == nil,
     "src/update/check_worker.lua still refuses outright when the transport "
     .. "is the bridge.  Android is the only bridge platform, so that branch "
     .. "IS the Android update path: it posts needs_full and the launcher "
     .. "sends the player to the GitHub releases page")
  ok(worker:find("big = big and true or nil", 1, true) ~= nil
     or worker:find("big", 1, true) ~= nil,
     "the bridge fetch no longer marks a payload transfer as big, so the "
     .. "main thread blocks for ~20 MB without drawing the downloading banner")
end

-- ---------------------------------------------------------------------------
section("3. the version comparison")
-- ---------------------------------------------------------------------------

local Semver = require("src.update.Semver")
local Version = require("src.core.Version")

ok(Semver.compare("0.7.6", "0.8.3") == -1,
   "0.7.6 does not compare lower than 0.8.3")
ok(Semver.compare("0.8.3", "0.8.3") == 0, "0.8.3 does not compare equal to itself")
ok(Semver.compare("0.10.0", "0.9.9") == 1,
   "0.10.0 compares lower than 0.9.9 -- the components are being compared as "
   .. "strings, so every release past .9 would be reported as older")
ok(Semver.compare("v0.8.3", "0.8.3") == 0,
   "a leading v makes two equal versions compare unequal, and GitHub tags "
   .. "carry one")
ok(Semver.parse("0.0.0-dev") == nil,
   "the working tree's 0.0.0-dev placeholder parses as a release, so a dev "
   .. "checkout would chase (and chainload) its own payload")

-- The working tree must be a build that can host its own payload, or the gate
-- below refuses every release this tree produces.
ok(type(Version.shell) == "number" and type(Version.minShell) == "number",
   "Version.shell / Version.minShell are not numbers")
ok(Version.minShell <= Version.shell,
   "Version.minShell (%s) exceeds Version.shell (%s): this build could not "
   .. "chainload its own payload", tostring(Version.minShell),
   tostring(Version.shell))

-- The dev short-circuit has to be in the worker, or an unstamped tree nags.
do
  local worker = stripComments(read("src/update/check_worker.lua") or "")
  ok(worker:find("0.0.0%-dev") ~= nil,
     "src/update/check_worker.lua no longer short-circuits the 0.0.0-dev "
     .. "placeholder, so a source checkout would be offered an update")
end

-- ---------------------------------------------------------------------------
section("4. the sums parsing, in the format release.yml produces")
-- ---------------------------------------------------------------------------

-- `sha256sum Gen2Recomped-* > sha256sums.txt` -- two spaces, bare filenames,
-- and the sums file deliberately outside the glob so it never lists itself.
do
  local name = Payload.name("0.8.3")
  local hex = ("9"):rep(64)
  local text = table.concat({
    hex .. "  Gen2Recomped-0.8.3-android.apk",
    ("a"):rep(64) .. "  " .. name,
    ("b"):rep(64) .. " *" .. "Gen2Recomped-0.8.3-windows.zip",
    ("c"):rep(64) .. "  ./Gen2Recomped-0.8.3-switch.zip",
  }, "\n") .. "\n"

  local Checkmod = require("src.update.Check")
  ok(Checkmod.parseSums(text, name) == ("a"):rep(64),
     "the checksum for %s was not found by its asset name -- the download "
     .. "would be rejected as unverifiable on every platform", name)
  ok(Checkmod.parseSums(text, "Gen2Recomped-0.8.3-windows.zip") == ("b"):rep(64),
     "the \"*\" binary marker breaks the filename match")
  ok(Checkmod.parseSums(text, "Gen2Recomped-0.8.3-switch.zip") == ("c"):rep(64),
     "a \"./\" prefix breaks the filename match")
  ok(Checkmod.parseSums(text, "sha256sums.txt") == nil,
     "parseSums invented a checksum for a name the file does not list")
  ok(Checkmod.parseSums(text, Payload.name("9.9.9")) == nil,
     "parseSums answered for a version the release does not carry")
  -- CRLF: a sums file that went through a Windows runner.
  ok(Checkmod.parseSums((text:gsub("\n", "\r\n")), name) == ("a"):rep(64),
     "a CRLF sums file is not parsed, so a Windows-produced release could "
     .. "not be verified")
  ok(next(Checkmod.parseSums("")) == nil,
     "parseSums on an empty body returned entries")
end

-- ---------------------------------------------------------------------------
section("5. the minShell refusal")
-- ---------------------------------------------------------------------------

local Boot = require("src.update.Boot")
do
  local newerRunnable = Payload.name("0.9.0")
  local newerTooNew = Payload.name("1.0.0")
  local older = Payload.name("0.5.0")

  local chosen, toDelete = Boot.select({
    { name = newerRunnable, engine = "0.9.0", minShell = 1 },
  }, "0.7.6", 1)
  ok(chosen == newerRunnable,
     "a newer payload whose minShell equals this shell was not selected: "
     .. "minShell is being compared with >= where it must be > (chosen=%s)",
     tostring(chosen))

  chosen, toDelete = Boot.select({
    { name = newerTooNew, engine = "1.0.0", minShell = 2 },
  }, "0.7.6", 1)
  ok(chosen == nil,
     "a payload demanding shell 2 was chainloaded by a shell-1 build (%s)",
     tostring(chosen))
  ok(#toDelete == 0,
     "a payload this shell cannot run yet was DELETED (%d victim(s)); it must "
     .. "be kept, because a later native build may be able to run it",
     #toDelete)

  chosen, toDelete = Boot.select({
    { name = older, engine = "0.5.0", minShell = 1 },
  }, "0.7.6", 1)
  ok(chosen == nil, "a payload older than the bundled engine was selected")
  ok(#toDelete == 1 and toDelete[1] == older,
     "a stale payload was not swept (%d victim(s))", #toDelete)

  chosen = Boot.select({
    { name = Payload.name("0.8.0"), engine = "0.8.0", minShell = 1 },
    { name = Payload.name("0.9.0"), engine = "0.9.0", minShell = 1 },
  }, "0.7.6", 1)
  ok(chosen == Payload.name("0.9.0"),
     "with two runnable payloads the highest was not chosen (%s)",
     tostring(chosen))
end

-- The worker's own gate, read off the worker: a >= here refuses a payload the
-- shell can host, which presents as "the update downloads and never applies".
do
  local worker = stripComments(read("src/update/check_worker.lua") or "")
  ok(worker:find("info.minShell > shell", 1, true) ~= nil,
     "src/update/check_worker.lua's gatePasses no longer compares "
     .. "info.minShell > shell; a >= there refuses a payload this shell can "
     .. "run and a < accepts one it cannot")
end

-- ---------------------------------------------------------------------------
section("6. the state the notify-only leg posts is one the launcher draws")
-- ---------------------------------------------------------------------------

-- The banner renders four of the eight states and nothing for the rest.  A leg
-- that posts "error" tells the player nothing, which is exactly what NX and
-- UWP did.  The launcher is read, never edited, by this check.
do
  local ui = required("src/import/RomImporter.lua",
    "it is the launcher, and the Check-to-banner joins asserted here are what "
    .. "stop a state being posted and never drawn")
  local drawn = BANNER
  ok(ui == nil or drawn ~= nil,
     "src/import/RomImporter.lua is present but no `upStatus` dispatch head "
     .. "could be read out of it, so the banner's vocabulary is unknown and "
     .. "every join assertion below would be vacuous")
  if ui and drawn then
    ok(next(drawn) ~= nil,
       "no upStatus literals found in src/import/RomImporter.lua, so the "
       .. "banner's vocabulary could not be read")
    ok(drawn.error ~= true and drawn.uptodate ~= true and drawn.idle ~= true,
       "the banner vocabulary read off the launcher contains a state the "
       .. "banner does not draw, so the refusal assertions above cannot fail")
    ok(drawn.needs_full == true,
       "the launcher banner does not render \"needs_full\", which is the "
       .. "state the notify-only leg posts -- the Switch and Xbox would again "
       .. "be told nothing at all")
    ok(drawn.ready == true,
       "the launcher banner does not render \"ready\", so a verified "
       .. "downloaded payload would never offer \"Restart to update\"")
    ok(drawn.available == true,
       "the launcher banner does not render \"available\", so the Update "
       .. "button is unreachable -- which is the whole Android bug")
    ok(ui:find("openURL", 1, true) ~= nil,
       "the launcher has no releases-page fallback left for the hosts that "
       .. "genuinely cannot fetch")
    ok(drawn.notify == true,
       "the launcher banner does not render \"notify\", the state Check.start() "
       .. "leaves on a host that cannot check at all.  Before it existed that "
       .. "leg ended on \"error\", which the banner hides, and the Switch and "
       .. "Xbox showed the player nothing whatsoever")

    -- THE TWO HALVES OF ONE FACT.  Check says which states are worth drawing;
    -- the launcher decides which it draws.  They were two lists and the
    -- launcher's was short by the only state that mattered.
    local Checkmod = require("src.update.Check")
    ok(type(Checkmod.STATUS) == "table" and next(Checkmod.STATUS) ~= nil,
       "Check.STATUS is missing or empty, so the launcher has nothing to "
       .. "derive its drawable states from and will go back to a hand list")
    for status, drawable in pairs(Checkmod.STATUS or {}) do
      if drawable then
        ok(drawn[status] == true,
           "Check.STATUS marks %q drawable and the launcher banner has no "
           .. "branch for it, so that state renders nothing at all", status)
      else
        ok(drawn[status] ~= true,
           "the launcher banner branches on %q, which Check.STATUS says is not "
           .. "a drawable state", status)
      end
    end
    for status in pairs(drawn) do
      ok(Checkmod.STATUS[status] ~= nil,
         "the launcher banner branches on %q, which is not a status "
         .. "Check.state() can report", status)
    end

    -- And the same join for the advice enum.
    ok(type(Checkmod.ADVICE) == "table" and next(Checkmod.ADVICE) ~= nil,
       "Check.ADVICE is missing or empty")
    ok(BANNER_ADVICE ~= nil,
       "no upAdvice branches found in the launcher, so the banner has gone "
       .. "back to one sentence for every refusal -- which is wrong on both "
       .. "consoles")
    if BANNER_ADVICE then
      -- "releases" is the launcher's else-branch and needs no named test; the
      -- three that change the wording must each be handled explicitly.
      for advice in pairs(Checkmod.ADVICE or {}) do
        if advice ~= "releases" and advice ~= "download" then
          ok(BANNER_ADVICE[advice] == true,
             "Check.advice() can return %q and the launcher banner never "
             .. "mentions it, so that host gets the default sentence -- which "
             .. "for a console is \"a new version needs a fresh download\" plus "
             .. "a button it has no browser for", advice)
        end
      end
      for advice in pairs(BANNER_ADVICE) do
        ok(Checkmod.ADVICE[advice] == true,
           "the launcher banner branches on advice %q, which Check.advice() "
           .. "cannot return", advice)
      end
    end

    -- A dead button is worse than no button: a console tap that opens nothing
    -- reads as a broken updater.  The two console advices must draw neither.
    local band = ui:match('upStatus == "needs_full" or upStatus == "notify".-\n    elseif')
      or ui:match('upStatus == "needs_full" or upStatus == "notify".-\n    end')
    ok(band ~= nil,
       "the notify/needs_full banner row could not be located in the launcher, "
       .. "so the assertions about which advices draw a button cannot run")
    if band then
      local otaArm = band:match('upAdvice == "ota" then(.-)else')
      local pkgArm = band:match('upAdvice == "package" then(.-)else')
      ok(otaArm ~= nil and not otaArm:find("action", 1, true),
         "the \"ota\" advice arm sets an action, so the Switch draws an "
         .. "\"Open releases\" button that opens nothing")
      ok(pkgArm ~= nil and not pkgArm:find("action", 1, true),
         "the \"package\" advice arm sets an action, so an Xbox container "
         .. "draws a button that opens nothing")
    end
    -- ANCHORED ON *THIS* CALL SITE, not on the function's name.  The first
    -- draft searched for "pcall(love.system.openURL" and passed a plant that
    -- removed the guard, because line 8851 of the same file has an unrelated
    -- pcall'd openURL for the save-folder link.  Shape 3b: a substring found
    -- somewhere in a 10,000-line file is not the call under test.  The
    -- negative is the one with teeth -- it names the unguarded form.
    ok(ui:find("love.system.openURL(self.Check.releaseUrl", 1, true) == nil,
       "the banner's releases-page tap calls love.system.openURL UNGUARDED; on "
       .. "a host whose implementation is a stub that takes the launcher down "
       .. "on a tap")
    ok(ui:find("pcall(love.system.openURL, self.Check.releaseUrl", 1, true) ~= nil,
       "the banner's releases-page tap no longer goes through pcall at all")
  end
end

-- ---------------------------------------------------------------------------
section("7. the hand-placed console payload, verified before it is trusted")
-- ---------------------------------------------------------------------------
--
-- THE ONE UPDATE PATH THE SWITCH AND XBOX HAVE WAS THE ONE NOBODY CHECKED.
-- src/update/check_worker.lua refuses a downloaded payload whose sha256 does
-- not match, and ports/switch/ota-launcher refuses a zip whose sum is missing
-- or wrong (ota_verify_sha256: "missing sum is ALWAYS reject").  The
-- hand-placed copy -- the whole console story outside the native OTA launcher,
-- because neither host can fetch -- went straight into love.filesystem.mount
-- with no integrity question asked at all.
--
-- The hashes below are the LIVE v0.8.3 release's own, read from
-- https://github.com/UNDERdecoded/Gen2Recomped/releases/download/v0.8.3/sha256sums.txt
-- on 2026-10-04 (HTTP 200, 1,171 bytes, 12 rows).  Using the real manifest
-- rather than a made-up one is what makes "verified" mean verified: a parser
-- that only handles invented input is a parser graded against itself.
local okS, Sideload = pcall(require, "src.update.Sideload")
ok(okS and type(Sideload) == "table",
   "src/update/Sideload.lua did not load: %s", tostring(Sideload))
if okS and type(Sideload) == "table" then
  -- PURITY FIRST, before anything calls into the module.  No love.* anywhere,
  -- because the verdict layer is driven from a plain Lua test and from the
  -- first line of love.load before a love runtime is set up at all.  This scan
  -- used to sit at the END of the section and a plant that added a love.*
  -- reference crashed the run before reaching it.
  local sl = required("src/update/Sideload.lua",
    "the sideload verdict layer is the only integrity check the consoles have")
  if sl then
    ok(stripComments(sl):find("love%.") == nil,
       "src/update/Sideload.lua calls into love.*, so its decisions can no "
       .. "longer be graded without a love runtime -- and a call that raises "
       .. "here takes the whole check down instead of failing")
  end

  -- EVERY call into the module goes through pcall, not just the one that
  -- probes an unknown verdict.  A plant that made Sideload touch love.* was
  -- diagnosed by the scan above and then STILL took the run down on the next
  -- bare mayMount, so the verdict line never printed -- and a checker that
  -- exits non-zero with no "N checks, M failed" reads as a broken checker.
  local function mayMount(v)
    local okc, r = pcall(Sideload.mayMount, v)
    return okc and r or false
  end

  local LIVE_PAYLOAD = Payload.name("0.8.3")
  local LIVE_SUM =
    "96fd608027b41973fe7bd4f650826e11b7234add0ef93049aaf7567ac1d9e11d"
  local LIVE_SUMS = table.concat({
    "e5a96030dd7c5ace9cf9e9be2a7da447e73b4a1ca46dea3c35ef24b0ce245760  "
      .. "Gen2Recomped-0.8.3-android.apk",
    "7d7dff3eae94010e3fcac0acd578d65c76dae5a93bad440711df35a521e06146  "
      .. "Gen2Recomped-0.8.3-switch.zip",
    "46cf7762d28d2139ed432272d6513a8e69239eb843530337e5a43ba3dbafc333  "
      .. "Gen2Recomped-0.8.3-xbox-uwp.zip",
    LIVE_SUM .. "  " .. LIVE_PAYLOAD,
  }, "\n")

  -- The release really does publish the manifest the sideload flow asks the
  -- player for, and really does list the payload in it.  Both halves matter:
  -- a manifest that exists and does not cover the payload is the "unlisted"
  -- refusal, and if that were the live state the whole feature would refuse
  -- every correct copy.
  ok(Payload.parseSums(LIVE_SUMS, LIVE_PAYLOAD) == LIVE_SUM,
     "the live v0.8.3 sha256sums.txt row for %s does not parse back to its "
     .. "hash, so the parser and the format release.yml publishes disagree",
     LIVE_PAYLOAD)

  local v, expect = Sideload.verdict(LIVE_PAYLOAD, LIVE_SUMS, LIVE_SUM)
  ok(v == Sideload.VERIFIED and expect == LIVE_SUM,
     "a payload whose hash matches the live manifest is %q, not %q",
     tostring(v), tostring(Sideload.VERIFIED))
  ok(Sideload.verdict(LIVE_PAYLOAD, LIVE_SUMS, LIVE_SUM:upper())
       == Sideload.VERIFIED,
     "the hash compare is case-sensitive, so an upper-case sha256sum (which "
     .. "some tools emit) is reported as a corrupt payload")

  -- One flipped nibble.  This is the shape of a truncated Device Portal
  -- upload or a microSD write that did not finish, which is the failure the
  -- whole section exists for.
  local bad = "06fd608027b41973fe7bd4f650826e11b7234add0ef93049aaf7567ac1d9e11d"
  ok(bad ~= LIVE_SUM, "the mismatch fixture equals the good hash, so the "
     .. "mismatch case is not being tested at all")
  local vm, em = Sideload.verdict(LIVE_PAYLOAD, LIVE_SUMS, bad)
  ok(vm == Sideload.MISMATCH and em == LIVE_SUM,
     "a payload whose hash differs from the manifest is %q, not %q -- a "
     .. "corrupt copy would be mounted as the game", tostring(vm),
     tostring(Sideload.MISMATCH))
  ok(not mayMount(Sideload.MISMATCH),
     "a mismatched payload may still be mounted")

  -- No manifest at all is the documented manual flow and must keep working,
  -- loudly.  Refusing here would brick every player who already hand-copies.
  ok(Sideload.verdict(LIVE_PAYLOAD, nil, nil) == Sideload.UNVERIFIED,
     "a payload with no %s beside it is not reported as unverified",
     Payload.SUMS)
  ok(mayMount(Sideload.UNVERIFIED),
     "a payload with no manifest is refused, which breaks the only update "
     .. "path the Switch and Xbox have")

  -- A manifest that is present and does not name this payload refuses: the
  -- player placed one deliberately, so two different releases got mixed.  An
  -- EMPTY manifest takes the same leg -- an empty file is a failed copy of the
  -- manifest far more often than a decision not to verify, and that is the
  -- distinction a `sumsText and sumsText ~= ""` guard would lose.
  local other = "7d7dff3eae94010e3fcac0acd578d65c76dae5a93bad440711df35a521e06146"
    .. "  Gen2Recomped-0.8.3-switch.zip"
  ok(Sideload.verdict(LIVE_PAYLOAD, other, LIVE_SUM) == Sideload.UNLISTED,
     "a manifest that does not list the payload beside it is not reported as "
     .. "unlisted")
  ok(Sideload.verdict(LIVE_PAYLOAD, "", LIVE_SUM) == Sideload.UNLISTED,
     "an EMPTY %s is treated as no manifest rather than as a manifest that "
     .. "does not cover the payload -- a failed copy of the manifest would "
     .. "then silently mount an unchecked payload", Payload.SUMS)
  ok(not mayMount(Sideload.UNLISTED),
     "an unlisted payload may still be mounted")
  ok(Sideload.verdict(LIVE_PAYLOAD, LIVE_SUMS, nil) == Sideload.MISMATCH,
     "a listed payload that could not be hashed is not refused -- the "
     .. "alternative is mounting an archive we were asked to verify and "
     .. "could not")

  -- THE JOIN, BOTH WAYS -- AND THE CONSTANT SET IS DISCOVERED, NOT LISTED.
  --
  -- The first draft enumerated the four constants by hand, and a plant that
  -- added a FIFTH one (Sideload.STALE, with no VERDICTS row) passed: the loop
  -- walked the list the check already knew about, so it could only ever
  -- confirm what the check had been told.  That is shape 7 -- prefer an
  -- invariant to a list, and where a list is unavoidable make it fail closed
  -- on what it does not cover.  So: every UPPER_CASE field on the module whose
  -- value is a string is a verdict by construction, and must have a row.
  local constants, nconst = {}, 0
  for k, v in pairs(Sideload) do
    if type(k) == "string" and type(v) == "string"
        and k == k:upper() and k:match("^[A-Z_]+$") then
      constants[#constants + 1] = v
      nconst = nconst + 1
    end
  end
  table.sort(constants)
  ok(nconst >= 4,
     "only %d verdict constant(s) were discovered on src/update/Sideload.lua "
     .. "where there are at least four, so this join is asserting over an "
     .. "almost-empty set", nconst)
  local seen = {}
  for _, k in ipairs(constants) do
    ok(Sideload.VERDICTS[k] ~= nil,
       "verdict %q has no row in Sideload.VERDICTS, so mayMount answers "
       .. "false for a verdict the module exports and the boot shell refuses "
       .. "a payload for a reason nothing decided", tostring(k))
    seen[k] = true
  end
  local extra = 0
  for k in pairs(Sideload.VERDICTS) do if not seen[k] then extra = extra + 1 end end
  ok(extra == 0,
     "Sideload.VERDICTS has %d row(s) that are not one of the exported "
     .. "verdict constants, so something returns a verdict no caller names",
     extra)
  -- pcall'd ON PURPOSE.  A plant that made this module touch love.* took the
  -- whole run down HERE with no verdict line at all -- which is worse than a
  -- failure, because `texlua tools/auto_update_check.lua` exiting non-zero
  -- with no "FAIL:" reads as a broken checker rather than a broken module.
  -- The purity scan below is what diagnoses that; this one must not pre-empt
  -- it by crashing.
  local okCall, unknown = pcall(Sideload.mayMount, "something-else")
  ok(okCall,
     "Sideload.mayMount RAISED: %s -- the verdict layer must stay pure Lua, "
     .. "see the love.* scan below for the likely cause", tostring(unknown))
  ok(not okCall or unknown == false,
     "mayMount returns a truthy answer for a verdict it does not know")

  -- The sentence is what the player actually gets, so it must name the file
  -- and, for a mismatch, BOTH hashes -- "checksum mismatch" with no numbers is
  -- the report that sent three platforms to the releases page in silence.
  local msg = Sideload.sentence(LIVE_PAYLOAD, Sideload.MISMATCH, LIVE_SUM, bad)
  ok(msg:find(LIVE_PAYLOAD, 1, true) ~= nil,
     "the mismatch sentence does not name the payload")
  ok(msg:find(LIVE_SUM:sub(1, 16), 1, true) ~= nil
       and msg:find(bad:sub(1, 16), 1, true) ~= nil,
     "the mismatch sentence does not carry both the expected and the actual "
     .. "hash, so the player cannot tell a corrupt copy from a wrong release")
  ok(Sideload.sentence(LIVE_PAYLOAD, Sideload.UNVERIFIED):find(
       Payload.SUMS, 1, true) ~= nil,
     "the unverified sentence does not name %s, so it tells the player "
     .. "nothing is checked without telling them how to have it checked",
     Payload.SUMS)

end

-- THE BOOT SHELL MUST ACTUALLY ASK.  Anchored on the FORM the gate takes --
-- the candidate append sitting inside a mayMount arm -- and not on a mention of
-- the module, because prose about the gate and an import of it both satisfy a
-- substring search.  That is shape 3e: an absence or membership scan with two
-- sources for one token grades neither.
do
  local boot = required("src/update/Boot.lua",
    "the boot shell is what mounts a hand-placed payload")
  if boot then
    local code = stripComments(boot)
    local arm = code:match("if Sideload%.mayMount%b()%s*then(.-)end")
    ok(arm ~= nil,
       "src/update/Boot.lua no longer gates on Sideload.mayMount at all, so a "
       .. "payload refused for its checksum is mounted anyway")
    ok(arm ~= nil and arm:find("candidates%[#candidates %+ 1%]") ~= nil,
       "the candidate list is built OUTSIDE the Sideload.mayMount arm, so the "
       .. "verdict is computed, printed and then ignored")
    ok(code:find("Sideload%.sentence") ~= nil,
       "src/update/Boot.lua computes a verdict without printing the sentence "
       .. "for it, so a refused payload is silent -- the exact shape of "
       .. "\"auto-update does nothing\"")
    ok(code:find("Payload%.sumsRel") ~= nil,
       "src/update/Boot.lua does not read the checksum manifest through "
       .. "Payload.sumsRel(), so the folder is spelled twice again")
    -- THE CHAINLOAD LINE REPORTED THE VERSION BEING REPLACED.  It read
    -- `(engine %s)` formatted with Version.engine -- the BUNDLED version --
    -- so the one line that says what the player is about to run named the
    -- thing they were moving off.  The negative is the one with teeth.
    ok(code:find('(engine %s)"):format(chosen, Version.engine)', 1, true) == nil,
       "the chainload line formats only Version.engine, which is the BUNDLED "
       .. "version being replaced rather than the payload's")
    -- The WHOLE statement, across its line breaks: the format string is on
    -- one line and its arguments on the next two, so a pattern that stops at
    -- the first newline can never see what is being substituted in -- and
    -- would have passed a plant that put the bundled version back.
    local stmt = code:match('print%(%("update: chainloading.-%)%)%)')
    ok(stmt ~= nil,
       "the chainload announcement could not be located, so the assertions "
       .. "about which version it reports cannot run")
    ok(stmt ~= nil and stmt:find("over bundled", 1, true) ~= nil,
       "the chainload line no longer distinguishes the payload's version from "
       .. "the bundled one it replaces")
    ok(stmt ~= nil and stmt:find("info.engine", 1, true) ~= nil,
       "the chainload line does not substitute the probed payload's own "
       .. "engine, so it reports the version being replaced")
    ok(stmt ~= nil and stmt:find("info.verdict", 1, true) ~= nil,
       "the chainload line does not say whether the payload it is about to "
       .. "run was checksum-verified or merely unverified")
  end
end

-- ONE SPELLING OF THE MANIFEST NAME, which is the recurring bug asked of a
-- fact that now has a Lua owner, a C owner and a workflow that produces it.
do
  local wf = required(".github/workflows/release.yml",
    "it is what publishes the manifest the sideload flow verifies against")
  if wf then
    ok(wf:find(Payload.SUMS, 1, true) ~= nil,
       "release.yml does not publish %q, so a player following the sideload "
       .. "instructions has nothing to download", Payload.SUMS)
  end
  local header = required("ports/switch/ota-launcher/include/ota_protocol.h",
    "its checksum URL and the Lua manifest name are the same fact in two "
    .. "languages")
  if header then
    local fmt = header:match("OTA_SUMS_URL_FMT[^\n]*\n?[^\n]*")
    ok(fmt ~= nil and fmt:find(Payload.SUMS, 1, true) ~= nil,
       "the Switch launcher's OTA_SUMS_URL_FMT does not end in %q, so the C "
       .. "side and src/update/Payload.lua name different files -- the "
       .. "cross-language half of this port's recurring bug", Payload.SUMS)
  end
  -- And exactly one Lua file may spell it.  Payload.lua is the owner; anything
  -- else is the ninth instance.
  local offenders = {}
  for _, rel in ipairs({
    "src/update/Boot.lua", "src/update/Check.lua", "src/update/Sideload.lua",
    "src/update/check_worker.lua", "src/update/Semver.lua",
  }) do
    local src = read(rel)
    if src and stripComments(src):find('"' .. Payload.SUMS .. '"', 1, true) then
      offenders[#offenders + 1] = rel
    end
  end
  ok(#offenders == 0,
     "%s spell(s) %q as a literal instead of asking src/update/Payload.lua",
     table.concat(offenders, ", "), Payload.SUMS)
  -- The owner really is the owner, so the scan above is not vacuous.
  local own = read("src/update/Payload.lua")
  ok(own ~= nil and own:find('"' .. Payload.SUMS .. '"', 1, true) ~= nil,
     "src/update/Payload.lua does not contain %q, so the one-spelling scan "
     .. "above is asserting over a name nothing defines", Payload.SUMS)
  -- One parser, too: the body moved out of Check.lua and a copy there would
  -- diverge the moment either side learned a new manifest quirk.
  local chk = read("src/update/Check.lua")
  if chk then
    ok(stripComments(chk):find("%(%%x%+%)%%s%+") == nil,
       "src/update/Check.lua carries its own sums-line pattern again instead "
       .. "of delegating to Payload.parseSums")
  end
end

-- ---------------------------------------------------------------------------
section("9. and this run was a whole run")
-- ---------------------------------------------------------------------------
--
-- A FLOOR ON THE NUMBER OF ASSERTIONS, which is checklist item 13 pointed at
-- the check itself.  `required()` above turns a missing committed file into a
-- named failure, but it only covers the four absences anybody has thought of.
-- This covers the rest: a pattern that stops matching, a block someone wraps
-- in a condition, a loop whose table comes back empty, any of which silently
-- removes assertions and leaves `N checks, 0 failed` looking like a full pass.
--
-- 260 is the count of everything that ran BEFORE this assertion, which is
-- what `ran` holds -- pinning it at the 261 the verdict line prints fails on
-- a clean tree, which is shape 2a (comparing a value against a number it is
-- not). Today's complete run prints 261; it was 218 before section 7 added
-- the sideload verifier's 43 assertions. This check declares
-- no argument slots in its `Run:` line, so tools/run_checks.py hands it no
-- arguments and the count is deterministic rather than input-dependent.  It
-- may only RISE: adding assertions is fine, losing them is the fault.  Raising
-- it is the same obligation as raising any pin -- name what moved, and confirm
-- the new floor still rejects the old state.
local FULL_RUN = 260
do
  local ran = checks
  ok(ran >= FULL_RUN,
     "only %d assertions ran where a whole run is at least %d. Something was "
     .. "skipped, not failed -- look above for a \"MISSING FROM THE TREE\" "
     .. "line, and if there is none then a pattern has stopped matching and is "
     .. "now asserting nothing over an empty set", ran, FULL_RUN)
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
