return function(root, backend, version, api, mode)
  return dofile(root .. "/tests/charge_required/fixture.lua").new(
    root,
    backend,
    version,
    api,
    "unified",
    false,
    mode == "rollback",
    "portable_ai_class_content",
    function(data, gen)
      if backend == "gen1" and gen == 3 then
        data.gen3Items._byId[13] = { name = "POTION", price = 300, pocket = "ITEMS" }
        data.gen3Items._byId[19] = { name = "FULL RESTORE", price = 3000, pocket = "ITEMS" }
      else
        data.items = data.items or {}
        for _, row in ipairs({
          { "POTION", gen == 1 and 20 or gen == 2 and 18 or 13 },
          { "FULL_RESTORE", gen == 1 and 16 or gen == 2 and 14 or 19 },
        }) do
          local id = backend == "gen2" and gen >= 2 and ("ITEM_%03d"):format(row[2]) or row[1]
          data.items[id] = { id = id, index = row[2], name = row[1]:gsub("_", " "), price = 300 }
        end
      end
    end,
    function(files)
      local Json = require("src.link.Json")
      local path = "mods/portable_ai_class_content/"
      local manifest = Json.decode(files[path .. "manifest.json"])
      manifest.content_format = "unified"
      files[path .. "manifest.json"] = Json.encode(manifest)
      files[path .. "case.txt"] = mode
    end
  )
end
