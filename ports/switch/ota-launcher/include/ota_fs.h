#ifndef GEN1_OTA_FS_H
#define GEN1_OTA_FS_H

#include "ota_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Read installed game version from sibling version.txt or NRO nacp-less stamp file.
 * Expects switch/gen1recomp/version.txt containing X.Y.Z. Returns 0 on success. */
int ota_fs_read_installed_version(const char *install_dir, char *out, size_t out_len);

/* SHA-256 hex (lowercase) of file. Returns 0 on success. */
int ota_fs_sha256_file(const char *path, char *out_hex, size_t out_len);

/* Apply verified temp payload (extracted game NRO) using atomic plan. Returns 0 on success. */
int ota_fs_atomic_replace_game(const char *install_dir, const char *verified_game_nro,
                               char *err, size_t err_len);

/* Atomically replace any named NRO under install_dir (copy→.part→rename). */
int ota_fs_atomic_replace_nro(const char *install_dir, const char *nro_name,
                              const char *verified_nro, char *err, size_t err_len);

/* Stage a new launcher + copy romfs bootstrap; chainload bootstrap_out next.
 * The running launcher cannot replace its own NRO on sdmc/FAT. */
int ota_fs_stage_launcher_bootstrap(const char *install_dir, const char *verified_launcher,
                                    char *bootstrap_out, size_t bootstrap_out_len, char *err,
                                    size_t err_len);

/* Hand off to game NRO via envSetNextLoad (Switch) or no-op stub (host). */
int ota_fs_handoff_to_game(const char *game_nro_path, char *err, size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
