# Cross-engine mod.input contract

Run from Gen2Recomped:

```sh
python3 tools/mod-input-contract-check/check.py --gen1 /path/to/gen1recomp --lua luajit --report /tmp/mod-input.json
```

The Gen1 checkout must be clean at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. No source is patched. Each native
loader executes `examples/portable_mod_input/main.lua` unchanged for two
independent mods, on Red, Gold, FireRed and Emerald. The checker verifies
the eight logical buttons, fixed-step edges/holds, independent sources,
foreign/idempotent token release, rebinding, invalid arguments and recovery,
then compares held/edge journals across the engines.

Use `--format unified` for unified API 2, `--api 3 --format unified` for API 3,
and `--gen2` to select an integration checkout. Unsupported manifests fail;
there is no silent downgrade. No ROM or native window is required.
