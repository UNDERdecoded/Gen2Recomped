#ifndef GEN1_OTA_PROTOCOL_H
#define GEN1_OTA_PROTOCOL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define OTA_CHECK_TIMEOUT_SEC 6
#define OTA_GAME_NRO_NAME "Gen2Recomped-game.nro"
#define OTA_LAUNCHER_NRO_NAME "gen2recomp.nro"
#define OTA_SAVE_DIR_NAME "pokemon-love2d"
#define OTA_INSTALL_DIR "switch/gen2recomp"
#define OTA_LAUNCHER_STAGED_SUFFIX ".staged"
#define OTA_BOOTSTRAP_ROMFS "romfs:/ota-bootstrap.nro"
#define OTA_BOOTSTRAP_SD_NAME "ota-bootstrap.nro"
/* THE REPOSITORY, ONCE.
 *
 * This read "UNDERdecodedHD/Gen2Recomped", which is not a repository that
 * exists: measured 2026-10-04, that slug answers HTTP 404 and
 * "UNDERdecoded/Gen2Recomped" answers 200.  So the quiet release check 404ed
 * on every launch, the launcher concluded "up to date or offline" and showed
 * nothing, and the Switch had no working update path at all -- while
 * src/update/Check.lua carried the correct slug and a comment describing this
 * exact mistake ("This read UNDERdecodedHD/... for a while, which is not a
 * repository that exists ... an updater that points at the wrong repo fails
 * exactly like an updater with no network").
 *
 * UNDERdecodedHD is the AUTHOR string -- the NACP author, the MSIX publisher,
 * the intro credit -- and is correct everywhere it appears as a name.  The
 * GitHub owner is UNDERdecoded.  The two had been conflated here and in
 * src/main.c's checksum URL, which is the same slug spelled a second time.
 *
 * Both URLs now derive from one definition, and
 * tools/auto_update_check.lua asserts it equals src/update/Check.lua's
 * Check.REPO -- the cross-language half of this port's recurring bug (the
 * same thing spelled differently in two places that never meet).
 */
#define OTA_REPO_SLUG "UNDERdecoded/Gen2Recomped"
#define OTA_RELEASES_API \
  "https://api.github.com/repos/" OTA_REPO_SLUG "/releases/latest"
/* Takes the release tag ("v0.8.3"). */
#define OTA_SUMS_URL_FMT \
  "https://github.com/" OTA_REPO_SLUG "/releases/download/%s/sha256sums.txt"

/* There is no Lua mirror of this wire format.  A comment here and a line in
 * README.md both pointed at a SwitchOta.lua under src/update that has never
 * existed in the tree; the semantics live in src/ota_protocol.c and are
 * exercised on the host by host/test_ota_protocol.c ("make host-test").  The
 * LOVE-side updater deliberately does NOT mirror them -- it is notify-only on
 * NX for a measured reason (docs/auto-update.md).
 *
 * tools/auto_update_check.lua asserts the dead PATH does not come back here
 * or in README.md.  It matches the path and not the bare name on purpose, so
 * prose about the removal (this paragraph) is not mistaken for the pointer --
 * the same distinction the banner-vocabulary scan in that file had to make. */

int ota_compare_semver(const char *a, const char *b);
int ota_is_ota_asset_name(const char *name);
int ota_version_from_ota_asset(const char *name, char *out, size_t out_len);

typedef struct {
  int ok; /* 1 on success */
  char reason[64];
  char tag[64];
  char version[32];
  char asset_name[128];
  char download_url[512];
} ota_release_t;

int ota_parse_release(const char *json_text, ota_release_t *out);

typedef struct {
  char status[32]; /* uptodate | available | error */
  char reason[64];
  char version[32];
  char asset_name[128];
  char download_url[512];
} ota_decision_t;

void ota_decide_update(const char *installed_version, const ota_release_t *release,
                       ota_decision_t *out);

/* sums: newline-separated sha256sums.txt body */
int ota_lookup_sum(const char *sums_text, const char *asset_name, char *out_hex,
                   size_t out_len);

typedef struct {
  int ok;
  char reason[64];
} ota_verify_t;

void ota_verify_sha256(const char *asset_name, const char *actual_hex,
                       const char *sums_text, ota_verify_t *out);

typedef struct {
  char steps[5][520]; /* human-readable ops */
  char preserve[256];
  char forbidden_delete[256];
  char forbidden_direct[256];
  char part_path[256];
  char game_nro[240];
  char launcher_nro[240];
  char launcher_part[256];
  char next_load[240];
} ota_apply_plan_t;

void ota_plan_atomic_apply(const char *install_dir, const char *verified_temp,
                           ota_apply_plan_t *out);

typedef struct {
  char action[32]; /* play_installed | keep_checking */
  char reason[64];
  char message[128];
} ota_offline_t;

typedef struct {
  int user_skip;
  int network_ok; /* 0 = offline/fail, 1 = ok, -1 = unknown */
  int api_error;
} ota_offline_events_t;

void ota_offline_policy(double elapsed_sec, const ota_offline_events_t *events,
                        ota_offline_t *out);

#ifdef __cplusplus
}
#endif

#endif /* GEN1_OTA_PROTOCOL_H */
