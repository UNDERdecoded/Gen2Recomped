package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Browser = require("src.render.ShaderBrowser")
local Json = require("src.link.Json")
local Menu = require("src.ui.ShaderPresetMenu")
local function fixture()
  local files, events, requests, removed = {}, {}, {}, {}
  local faults = {}
  local validations = 0
  local fs = {
    getInfo = function(path)
      return files[path] and { type = "file", size = #files[path] }
    end,
    createDirectory = function(path)
      if faults.mkdir then
        return nil, "disk full"
      end
      files[path] = "dir"
      return true
    end,
    write = function(path, bytes)
      if faults.write then
        return nil, "write failed"
      end
      files[path] = bytes
      return true
    end,
    remove = function(path)
      removed[path] = true
      files[path] = nil
      return true
    end,
  }
  local b = Browser.new({
    fs = fs,
    root = "/test with spaces",
    available = function()
      if faults.unavailable then
        return nil, "missing helper"
      end
      return true
    end,
    start = function(job)
      if faults.start then
        error("spawn failed")
      end
      requests[#requests + 1] = job
      return {
        pop = function()
          return table.remove(events, 1)
        end,
      }, {
        getError = function()
          return faults.thread
        end,
      }
    end,
    validate = function(directory)
      validations = validations + 1
      T.check(directory:match("/prepared$"), "private prepared folder")
      if faults.gpu then
        return nil, "GPU rejected candidate"
      end
      return true
    end,
  })
  local function post(e)
    events[#events + 1] = Json.encode(e)
    b:poll()
  end
  return b, files, events, requests, faults, post, function()
    return validations
  end
end
local id = "local:slang-" .. string.rep("a", 32)
do
  local b, files, events, requests, f, post, count = fixture()
  T.check(b:start("catalog"), "catalog starts")
  T.eq(#requests, 1, "one worker")
  T.check(not b:start("catalog"), "duplicate blocked")
  T.eq(requests[1].request.destination, "/test with spaces/shader-presets", "active data root destination")
  post({ kind = "catalog", entries = { { name = "LCD", path = "handheld/lcd.slangp" } } })
  T.check(not b.busy, "catalog complete")
  T.eq(b.entries[1].name, "LCD", "records")
  T.check(b:start("install", "handheld/lcd.slangp"), "install starts")
  local rel = b.relative
  post({ kind = "status", message = "Converting" })
  T.eq(b.message, "Converting", "progress")
  T.eq(files[rel .. "/approve"], nil, "no early approval")
  post({ kind = "ready" })
  T.eq(count(), 1, "GPU validation once")
  T.check(files[rel .. "/approve"] ~= nil, "approval after GPU")
  post({ kind = "installed", id = id })
  T.eq(b.installed["handheld/lcd.slangp"], id, "installed receipt")
  T.check(not b.busy, "done")
  T.eq(b.result, "installed", "done result")
end
for _, fault in ipairs({ "unavailable", "mkdir", "write", "start" }) do
  local b, files, e, r, f = fixture()
  f[fault] = true
  T.check(not b:start("catalog"), fault .. " start failure")
  T.check(not b.busy, "not running")
end
for _, fault in ipairs({ "gpu", "thread", "write" }) do
  local b, files, e, r, f, post = fixture()
  T.check(b:start("install", "handheld/lcd.slangp"), "start fault")
  local rel = b.relative
  f[fault] = true
  if fault == "thread" then
    b:poll()
  else
    post({ kind = "ready" })
  end
  T.eq(files[rel .. "/approve"], nil, "failed job never approved")
  T.check(b.error ~= nil, "failure recorded")
  T.check(not b.busy, "failed retired")
end
do
  local b, files, e, r, f, post, count = fixture()
  b:start("install", "handheld/lcd.slangp")
  local rel = b.relative
  b:cancel()
  T.check(files[rel .. "/cancel"] ~= nil, "cancellation signal")
  post({ kind = "ready" })
  T.eq(count(), 0, "late ready ignored")
  T.eq(files[rel .. "/approve"], nil, "no late approval")
  T.eq(b.installed["handheld/lcd.slangp"], nil, "not installed")
end
for _, event in ipairs({
  { kind = "catalog", entries = { { path = "../../secret", name = "BAD" } } },
  { kind = "catalog", entries = "bad" },
  { kind = "installed", id = "local:../../secret" },
  { kind = "catalog", entries = { { path = "handheld/test.slangp", name = "\nBAD" } } },
}) do
  local b, files, e, r, f, post = fixture()
  b:start("catalog")
  post(event)
  T.check(b.error ~= nil, "bad response refused")
  T.check(not b.busy, "bad response retired")
end
do
  local b, files, events = fixture()
  b:start("catalog")
  events[1] = "not json"
  b:poll()
  T.check(b.error ~= nil and not b.busy, "malformed JSON retired")
end
-- Actual shared menu actions: acquisition and activation are separate; exiting cancels.
do
  local b, files, e, r, f, post = fixture()
  local pushed = {}, nil
  local game = {
    save = { options = { shaderPreset = "keep" } },
    stack = {
      push = function(_, s)
        pushed[#pushed + 1] = s
      end,
      pop = function() end,
    },
    input = {
      wasPressed = function()
        return false
      end,
    },
  }
  local selected = {}
  local presets = {
    refresh = function()
      selected.refresh = true
    end,
    select = function(_, opts, which)
      selected.id = which
      opts.shaderPreset = which
      return true
    end,
  }
  local m = Menu.browser(game, presets, b)
  post({ kind = "catalog", entries = { { path = "handheld/lcd.slangp", name = "LCD" } } })
  m:update()
  T.eq(m.rows[1].label, "LCD", "catalog displayed")
  m.rows[1].activate()
  T.check(b.busy, "download action starts install")
  T.eq(game.save.options.shaderPreset, "keep", "acquisition preserves choice")
  post({ kind = "ready" })
  post({ kind = "installed", id = id })
  T.eq(game.save.options.shaderPreset, "keep", "installation preserves choice")
  m.rows[1].activate()
  T.eq(selected.id, id, "explicit selection activates")
  T.eq(game.save.options.shaderPreset, id, "selection saved")
  b:start("install", "handheld/lcd.slangp")
  local rel = b.relative
  m:exit()
  T.check(files[rel .. "/cancel"] ~= nil, "native state exit cancels")
end
do
  local a, fa = fixture()
  local b, fb = fixture()
  a:start("catalog")
  b:start("catalog")
  Browser.shutdown()
  T.check(
    fa[a.relative .. "/cancel"] ~= nil and fb[b.relative .. "/cancel"] ~= nil,
    "shutdown cancels every active job"
  )
end
T.finish("shader browser")
