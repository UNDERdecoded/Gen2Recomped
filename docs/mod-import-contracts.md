# Required and optional mod imports

Declare player-supplied files in `required_imports` or `optional_imports`.
Required files are validated before the entry chunk runs; missing or invalid
files block that mod and its hard dependents with an attributed import reason.
An optional file never blocks startup. The launcher offers its import action
separately, and in-game mod options list both kinds of declarations.

```json
{
  "required_imports": [{
    "id": "example",
    "file": "example.bin",
    "size": 3,
    "md5": ["900150983cd24fb0d6963f7d28e17f72"]
  }],
  "optional_imports": [{
    "id": "extra",
    "name": "Extra resource pack",
    "file": "extra.pack",
    "format": "raw",
    "extensions": [".pack"],
    "max_size": 67108864,
    "verify": "mod"
  }]
}
```

The example required file contains the three bytes `abc`. Authors supply the
hashes for their own real sources; a digest can be one string, a list, or a
comma-separated legacy string. `verify: "mod"` delegates content validation to
the mod; the engine still enforces the declared size limits and scoped access.
Use that option only when the mod checks the file's structure itself.

Bare filenames default to `mods/<id>/baseroms/<file>`. Existing literal paths
containing `/`, explicit `root: "mod"` paths and `root: "save"` declarations
retain their original routing. A bare file already present directly in a mod
folder remains usable at that location. The mod read/info/path accessors resolve
both declared spellings without moving that existing file.

`mod.imports:info(id)` exposes the actual size, `required` flag and verification
method (`md5`, `mod`, or legacy `size`). Portable declarations return `nil` plus
a reason while unavailable. Existing literal-path declarations retain their
`ready` metadata. `mod.imports:list()` includes both required and optional files.

```lua
local info, reason = mod.imports:info("extra")
if info then
  local bytes, err = mod.imports:read("extra", 0, math.min(info.size, 4096))
end
```

Portable reads require an explicit non-negative integer offset and length;
one read is limited to 8 MiB. Out-of-bounds, undeclared and unvalidated reads
fail. Large imports never fall back to allocating the entire file when a host
lacks random access. The older whole-file accessor remains available for
validated literal-path declarations.

Copies and MD5 validation stream in bounded chunks on desktop, mobile and
console. N64 imports accept the three byte orders and recognized 512-byte
headers; new portable installs store canonical big-endian bytes. Existing
literal-path N64 files retain their bytes, with canonical hash validation.
Validation results are reused while file size and modification time match;
changed metadata causes revalidation.

New files are staged under the engine's import staging folder. Size, signature
and applicable digest checks finish before atomic publication. Failed reads,
short writes, bad hashes or failed publication leave the previously installed
file intact. Original picker sources are not modified by this copy path.

After a blocked required import becomes available in-game, the manager offers
the existing apply/restart flow. Optional imports use the existing ready event
without forcing a restart. These contracts are ROM-free tested with synthetic
data; physical-device acceptance and background job integration remain separate.
