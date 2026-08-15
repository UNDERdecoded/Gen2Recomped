/*
 * gen2recomp Switch OTA launcher
 *
 * Quiet by default: checks GitHub Releases with no UI. Only shows the
 * branded launcher-style screen when an update is available. Downloads the
 * same SD zip (Gen2Recomped-*-switch.zip), verifies SHA-256, replaces game +
 * launcher NROs, then envSetNextLoad. Never touches pokemon-love2d/.
 * LÖVE self-updater stays off on NX.
 */

#include "ota_fs.h"
#include "ota_net.h"
#include "ota_protocol.h"
#include "ota_ui.h"
#include "ota_unzip.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SWITCH__)
#include <sys/stat.h>
#include <switch.h>
#include <unistd.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif

#define SD_INSTALL_DIR "sdmc:/switch/gen2recomp"
#define CHECK_TIMEOUT_MS (OTA_CHECK_TIMEOUT_SEC * 1000L)
#define GAME_MEMBER_IN_ZIP "switch/gen2recomp/" OTA_GAME_NRO_NAME
#define LAUNCHER_MEMBER_IN_ZIP "switch/gen2recomp/" OTA_LAUNCHER_NRO_NAME

typedef struct {
  const char *detail;
  float base;
  float span;
} download_progress_ctx_t;

static void on_download_progress(void *userdata, double fraction) {
  download_progress_ctx_t *ctx = (download_progress_ctx_t *)userdata;
  if (!ctx) return;
  float p = ctx->base;
  if (fraction >= 0.0) p += ctx->span * (float)fraction;
  else p += ctx->span * 0.1f;
  if (p > ctx->base + ctx->span) p = ctx->base + ctx->span;
  ota_ui_show_progress("Step 1/3: Downloading...", ctx->detail, p);
}

static void show_update_error(const char *title, const char *friendly, const char *technical,
                              const char *installed) {
  ota_ui_alert_error(title, friendly, technical, installed);
}

static int run_update_flow(const char *install_dir) {
  char installed[64] = "0.0.0";
  (void)ota_fs_read_installed_version(install_dir, installed, sizeof(installed));

  char *json = NULL;
  size_t json_len = 0;
  char err[256];
  err[0] = '\0';

  if (ota_net_download_buffer(OTA_RELEASES_API, CHECK_TIMEOUT_MS, &json, &json_len, err,
                              sizeof(err)) != 0) {
    free(json);
    return 0; /* offline / timeout — play installed, no UI */
  }

  ota_release_t rel;
  if (!ota_parse_release(json, &rel)) {
    free(json);
    return 0;
  }
  free(json);

  ota_decision_t dec;
  ota_decide_update(installed, &rel, &dec);
  if (strcmp(dec.status, "uptodate") == 0 || strcmp(dec.status, "error") == 0) {
    return 0;
  }

  if (!ota_ui_prompt_update(installed, dec.version)) {
    return 0;
  }

  char updates_dir[192];
  char zip_path[256];
  char sums_path[256];
  snprintf(updates_dir, sizeof(updates_dir), "%s/updates", install_dir);
  snprintf(zip_path, sizeof(zip_path), "%s/updates/%s", install_dir, dec.asset_name);
  snprintf(sums_path, sizeof(sums_path), "%s/updates/sha256sums.txt", install_dir);

#if defined(__SWITCH__)
  mkdir(updates_dir, 0755);
#endif

  download_progress_ctx_t dl_ctx = {"This may take a minute.", 0.f, 0.5f};
  ota_ui_show_progress("Step 1/3: Downloading...", dl_ctx.detail, dl_ctx.base);
  if (ota_net_download_file(dec.download_url, zip_path, 180000L, err, sizeof(err),
                              on_download_progress, &dl_ctx) != 0) {
    show_update_error("Download failed",
                      "Could not download the update. Check Wi-Fi and try again.", err, installed);
    return 0;
  }

  ota_ui_show_progress("Step 2/3: Verifying...", "Checking file integrity.", 0.55f);
  char sums_url[512];
  snprintf(sums_url, sizeof(sums_url),
           "https://github.com/UNDERdecodedHD/Gen2Recomped/releases/download/%s/sha256sums.txt",
           rel.tag);
  if (ota_net_download_file(sums_url, sums_path, CHECK_TIMEOUT_MS, err, sizeof(err), NULL,
                            NULL) != 0) {
    remove(zip_path);
    show_update_error("Could not verify", "Downloaded file could not be checked.", err, installed);
    return 0;
  }

  FILE *sf = fopen(sums_path, "rb");
  if (!sf) {
    remove(zip_path);
    show_update_error("Could not verify", "Could not read checksum file.", "fopen sums failed",
                      installed);
    return 0;
  }
  fseek(sf, 0, SEEK_END);
  long slen = ftell(sf);
  fseek(sf, 0, SEEK_SET);
  char *sums = (char *)malloc((size_t)slen + 1);
  if (!sums) {
    fclose(sf);
    remove(zip_path);
    show_update_error("Could not verify", "Not enough memory to verify update.", "malloc failed",
                      installed);
    return 0;
  }
  fread(sums, 1, (size_t)slen, sf);
  sums[slen] = '\0';
  fclose(sf);

  ota_ui_show_progress("Step 2/3: Verifying...", "Computing checksum...", 0.65f);
  char hex[96];
  if (ota_fs_sha256_file(zip_path, hex, sizeof(hex)) != 0) {
    free(sums);
    remove(zip_path);
    show_update_error("Could not verify", "Could not read downloaded update file.",
                      "sha256 file read failed", installed);
    return 0;
  }
  ota_verify_t ver;
  ota_verify_sha256(dec.asset_name, hex, sums, &ver);
  free(sums);
  if (!ver.ok) {
    remove(zip_path);
    show_update_error("Update check failed",
                      "Downloaded file did not match expected checksum.", ver.reason, installed);
    return 0;
  }

  char extracted[256];
  char extracted_launcher[256];
  snprintf(extracted, sizeof(extracted), "%s/updates/Gen2Recomped-game.nro.verified", install_dir);
  snprintf(extracted_launcher, sizeof(extracted_launcher), "%s/updates/gen2recomp.nro.verified",
           install_dir);

#if defined(__SWITCH__)
  ota_ui_show_progress("Step 3/3: Installing...", "Keeping your saves safe.", 0.8f);
  if (ota_unzip_extract_file(zip_path, GAME_MEMBER_IN_ZIP, extracted, err, sizeof(err)) != 0) {
    if (ota_unzip_extract_file(zip_path, OTA_GAME_NRO_NAME, extracted, err, sizeof(err)) != 0) {
      remove(zip_path);
      show_update_error("Could not extract",
                        "Update zip is missing game files or is corrupted.", err, installed);
      return 0;
    }
  }

  if (ota_fs_atomic_replace_game(install_dir, extracted, err, sizeof(err)) != 0) {
    remove(extracted);
    remove(zip_path);
    show_update_error("Could not install",
                      "Could not replace game on microSD. Free up space and try again.", err,
                      installed);
    return 0;
  }
  remove(extracted);

  int have_launcher = 0;
  if (ota_unzip_extract_file(zip_path, LAUNCHER_MEMBER_IN_ZIP, extracted_launcher, err,
                             sizeof(err)) == 0 ||
      ota_unzip_extract_file(zip_path, OTA_LAUNCHER_NRO_NAME, extracted_launcher, err,
                             sizeof(err)) == 0) {
    have_launcher = 1;
  }
  if (!have_launcher) {
    remove(zip_path);
    show_update_error("Could not extract",
                      "Update zip is missing launcher files.", err, installed);
    return 0;
  }

  char bootstrap_path[256];
  bootstrap_path[0] = '\0';
  if (ota_fs_stage_launcher_bootstrap(install_dir, extracted_launcher, bootstrap_path,
                                      sizeof(bootstrap_path), err, sizeof(err)) != 0) {
    remove(extracted_launcher);
    remove(zip_path);
    show_update_error("Could not install",
                      "Game updated but launcher could not be staged. Reinstall from the SD zip.",
                      err, installed);
    return 0;
  }
  remove(extracted_launcher);

  char vpath[192];
  snprintf(vpath, sizeof(vpath), "%s/version.txt", install_dir);
  FILE *vf = fopen(vpath, "wb");
  if (vf) {
    fprintf(vf, "%s\n", dec.version);
    fclose(vf);
  }

  ota_ui_show_progress("Ready", "Finishing update...", 1.0f);
  svcSleepThread(600000000ULL);
  remove(zip_path);
  ota_ui_shutdown();

  if (ota_fs_handoff_to_game(bootstrap_path, err, sizeof(err)) != 0) {
    show_update_error("Could not install", "Launcher bootstrap failed.", err, installed);
    return 0;
  }
  return 2; /* chainload bootstrap; main must not hand off to game */
#else
  (void)extracted;
  (void)extracted_launcher;
#endif
  remove(zip_path);
  ota_ui_shutdown();
  return 0;
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

  const char *install = SD_INSTALL_DIR;
  int update_rc = 0;

#if defined(__SWITCH__)
  socketInitializeDefault();
  padConfigureInput(1, HidNpadStyleSet_NpadStandard);
  if (ota_net_init() == 0) {
    update_rc = run_update_flow(install);
    ota_net_shutdown();
  }
#else
  update_rc = run_update_flow(install);
#endif

  if (update_rc == 2) {
#if defined(__SWITCH__)
    socketExit();
#endif
    return 0;
  }

  char game[192];
  snprintf(game, sizeof(game), "%s/%s", install, OTA_GAME_NRO_NAME);
  char err[128];
  err[0] = '\0';
  if (ota_fs_handoff_to_game(game, err, sizeof(err)) != 0) {
    ota_ui_missing_game();
  }

  ota_ui_shutdown();

#if defined(__SWITCH__)
  socketExit();
#endif
  return 0;
}
