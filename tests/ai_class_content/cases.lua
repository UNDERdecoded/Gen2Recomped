return function(root, backend, version, api)
  local rows = {}
  for _, mode in ipairs({ "register", "patch", "override", "delete-item", "brain", "remove", "rollback" }) do
    local f = dofile(root .. "/tests/ai_class_content/fixture.lua")(root, backend, version, api, mode)
    local T, h = f.T, f.e and f.e.api.content.ai_classes
    local raw = f.result.loader.content.ai_classes:get("PORTABLE_METADATA_CLASS")
    T.eq(#f.result.errors > 0, mode == "rollback", "AI class entry outcome " .. mode)
    if mode == "rollback" then
      T.eq(raw, nil, "failed entry rolls AI class operation back")
      rows[#rows + 1] = { mode = mode, failed = true, absent = raw == nil }
    else
      local state = f.e.state
      T.eq(state.writeDetached, true, "AI class write result is detached")
      T.eq(state.iterationDetached, true, "AI class iteration is detached")
      if mode ~= "remove" then
        T.eq(state.readDetached, true, "AI class get is detached")
        if mode == "brain" then
          T.eq(raw.uses, nil, "class override replaces omitted native fields")
        else
          T.eq(raw.uses, mode == "override" and 1 or 2, "native class uses survive detached edits")
        end
        if mode ~= "delete-item" and mode ~= "brain" then
          local canonical = (mode == "patch" or mode == "override") and "FULL_RESTORE" or "POTION"
          T.eq(state.current.item, canonical, "public class item is canonical")
          if backend == "gen2" and f.gen >= 2 then
            local index = canonical == "POTION" and (f.gen == 2 and 18 or 13) or (f.gen == 2 and 14 or 19)
            T.eq(raw.item, ("ITEM_%03d"):format(index), "native class receives actual fixture item key")
          end
        end
      else
        T.eq(raw, nil, "removed class has no native record")
      end
      rows[#rows + 1] = { mode = mode, failed = false, state = state }
      -- Opaque API handle is an export, not part of the metadata observations.
      T.check(h ~= nil, "class accessor survives entry")
    end
    f.close()
  end
  return rows
end
