-- Hold only the final OS publication call, to exercise the real worker's
-- cancellation/commit boundary while the main thread keeps pumping.
require("love.thread")
require("love.filesystem")
require("love.timer")
require("love.system")
local publish = require("src.net.DownloadPublish")
package.loaded["src.net.DownloadPublish"] = function(source, target)
  if target:sub(-18) == "/delay-publish.bin" then love.timer.sleep(.25) end
  return publish(source, target)
end
assert(love.filesystem.load("src/net/download_worker.lua"))(...)
