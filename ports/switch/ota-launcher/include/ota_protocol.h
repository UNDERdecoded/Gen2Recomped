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
#define OTA_RELEASES_API \
  "https://api.github.com/repos/UNDERdecodedHD/Gen2Recomped/releases/latest"

/* Mirrors src/update/SwitchOta.lua — keep semantics in lockstep. */

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
