# Reusing a frozen engine payload on mobile

Both mobile build scripts accept `--game-love /absolute/path/game.love`.
This validates the archive, import manifests and optional `--version`, then
copies its bytes unchanged. Neither mobile job restamps, adds credentials or
bundles extra mods into that archive. Without the option, the existing source
packaging path is retained.

```sh
GEN2_APPLICATION_ID=org.example.nativepreview GEN2_APP_NAME='Native Preview' \
  bash scripts/build_android.sh --game-love /path/game.love --version 1.2.3
GEN2_BUNDLE_ID=org.example.nativepreview \
  bash scripts/build_ios.sh --fetch --game-love /path/game.love --version 1.2.3
```

Use a separate app identifier for a preview so it can coexist with a stable
installation. Android keeps the committed signing key. iOS device signing and
installation still require the normal Apple provisioning steps.

`LOVE_SOURCE_REF` and `APPLE_DEPENDENCIES_REF` also accept full commit IDs,
allowing release jobs to pin both fetched iOS inputs. Builds without these
overrides retain their existing defaults. Use a fresh `love-src` directory when
changing those pins; `--fetch` deliberately reuses an existing source tree.

The SDK-free payload contract tests check validation and byte preservation.
They do not establish that a native runtime builds, starts or plays a game.
