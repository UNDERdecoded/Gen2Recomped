-- Real SDK/asset owners; only image decoding and GPU resources are device seams.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Assets = require('src.render.Assets')
local oldImage, oldPixels = love.graphics.newImage, love.image
local resources = {}
local function resource(label)
  local value = {label = label, releases = 0}
  function value:release()
    self.releases = self.releases + 1
    if self.label == 'bad.png' then error('synthetic device release failure') end
  end
  resources[#resources + 1] = value
  return value
end
love.image = {newImageData = function(path)
  if type(path) == 'string' and path:find('assets/generated/', 1, true) == 1 then
    error('native sheet absent')
  end
  return resource(path)
end}
love.graphics.newImage = function(path)
  if type(path) == 'string' and path:find('assets/generated/', 1, true) == 1 then
    error('native sheet absent')
  end
  return resource(path)
end
local run = T.sdk.loadMods({'mods/cache_probe'}, {
  data = T.fixtures.fresh(), fs = T.sdk.memfs({
    ['mods/cache_probe/manifest.json'] = [[{"id":"cache_probe","name":"Cache probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
    ['mods/cache_probe/main.lua'] = [[
      local mod = ...
      local Assets = require('src.render.Assets')
      local state = {invalidates=0, releases=0, legacy=0, tail=0, textures={}}
      Assets.register(function() state.legacy = state.legacy + 1 end)
      Assets.register{invalidate=function()
        state.invalidates = state.invalidates + 1
        state.textures = {}
      end, release=function() state.releases = state.releases + 1 end}
      Assets.register{release=function() error('synthetic cache release failure') end}
      Assets.register{release=function() state.tail = state.tail + 1 end}
      mod.exports.state = state
    ]],
  }),
})
T.eq(#run.errors, 0, 'table hooks register through the unchanged SDK contract')
local state = assert(run.loader.exports.cache_probe).state
local image = Assets.image('soft.png')
state.textures.keep = image
local invalidates, legacy, releases = state.invalidates, state.legacy, state.releases
Assets.flush()
T.eq(state.invalidates, invalidates + 1, 'soft flush invokes table invalidators')
T.eq(state.legacy, legacy + 1, 'legacy function invalidators remain compatible')
T.eq(next(state.textures), nil, 'consumer cache actually empties on refresh')
T.eq(state.releases, releases, 'soft refresh never closes the session consumer')
T.eq(image.releases, 0, 'a live renderer can retain its image across soft refresh')
local bad = Assets.image('bad.png')
local good = Assets.image('good.png')
T.eq(Assets.image('good.png'), good, 'session retains central image identity')
local mutable = Assets.imageData('mutable.png')
local blank = Assets.image('assets/generated/missing-a.png')
T.eq(Assets.image('assets/generated/missing-b.png'), blank, 'missing native sheets share one blank resource')
local releaseSession = Assets.releaseSession
T.eq(type(releaseSession), 'function', 'Gen1 releaseSession entrypoint exists')
invalidates, legacy, releases = state.invalidates, state.legacy, state.releases
local tail = state.tail
if type(releaseSession) == 'function' then
  T.check(pcall(releaseSession), 'one failing cache or device cannot strand session retirement')
  T.eq(bad.releases, 1, 'faulty central image was attempted once')
  T.eq(good.releases, 1, 'remaining central image is released')
  T.eq(mutable.releases, 0, 'caller-owned mutable pixels are retained')
  T.eq(blank.releases, 1, 'aliased native blank is released only once')
  T.eq(state.releases, releases + 1, 'table release callback reaches its consumer')
  T.eq(state.tail, tail + 1, 'a failing release callback leaves later callbacks reachable')
  T.eq(state.invalidates, invalidates, 'hard release does not masquerade as soft invalidate')
  T.eq(state.legacy, legacy, 'hard release does not invoke legacy invalidators')
  releaseSession()
  T.eq(good.releases, 1, 'repeated session retirement cannot double-release central images')
  T.eq(blank.releases, 1, 'repeated retirement cannot double-release native blank')
  T.check(Assets.image('good.png') ~= good, 'next session can populate a new real image')
  T.check(Assets.image('assets/generated/missing-a.png') ~= blank, 'next session never reuses a released blank')
  -- Even a soft invalidation must not make the separately owned blank escape
  -- the next hard release merely because its central aliases were cleared.
  local retainedBlank = Assets.image('assets/generated/missing-b.png')
  Assets.invalidate()
  T.eq(retainedBlank.releases, 0, 'soft invalidation keeps the fallback resource alive')
  releaseSession()
  T.eq(retainedBlank.releases, 1, 'hard retirement still releases the retained fallback')
end
-- Execute the actual native launcher-return closure. Only the launcher UI
-- opening is replaced; SDK teardown and asset resource owners stay real.
local file = assert(io.open('main.lua', 'rb'))
local source = file:read('*a'); file:close()
local nativeReturn = assert(source:gsub('\r\n', '\n'):match('\nlocal function returnToLauncher%(%).-\nend\n'))
local opens = 0
local env = setmetatable({Game={}, openLauncher=function() opens = opens + 1 end}, {__index=_G})
local chunk = assert(loadstring(nativeReturn .. '\nreturn returnToLauncher', '@native-launcher-asset-boundary'))
setfenv(chunk, env)
local returnToLauncher = chunk()
local liveImage = Assets.image('launcher.png')
releases = state.releases
returnToLauncher()
T.eq(liveImage.releases, 1, 'actual launcher return releases its native central image')
T.eq(state.releases, releases + 1, 'actual launcher return closes downstream asset consumers')
T.eq(Assets.loader, nil, 'native loader detaches after launcher asset release')
T.eq(opens, 1, 'retired session opens launcher once')
run.release()
love.graphics.newImage, love.image = oldImage, oldPixels
T.finish('asset hook tables and session resource lifetime through real SDK')
