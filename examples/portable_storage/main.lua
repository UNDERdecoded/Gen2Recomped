local mod = ...
local storage = mod.storage
for _, method in ipairs({
  "context",
  "selected",
  "read",
  "write",
  "readBytes",
  "writeBytes",
  "list",
  "delete",
}) do
  local name = method
  mod.exports[name] = function(...)
    return storage[name](storage, ...)
  end
end
