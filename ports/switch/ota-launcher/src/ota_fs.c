#include "ota_fs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SWITCH__)
#include <switch.h>
#include <mbedtls/sha256.h>
#include <sys/stat.h>
#include <unistd.h>
#else
#include <unistd.h>
#endif

int ota_fs_read_installed_version(const char *install_dir, char *out, size_t out_len) {
  if (!out || out_len == 0) return -1;
  out[0] = '\0';
  char path[256];
  snprintf(path, sizeof(path), "%s/version.txt", install_dir ? install_dir : OTA_INSTALL_DIR);
  FILE *fp = fopen(path, "rb");
  if (!fp) return -1;
  if (!fgets(out, (int)out_len, fp)) {
    fclose(fp);
    return -1;
  }
  fclose(fp);
  /* trim */
  size_t n = strlen(out);
  while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == '\r' || out[n - 1] == ' ')) {
    out[--n] = '\0';
  }
  return n > 0 ? 0 : -1;
}

int ota_fs_sha256_file(const char *path, char *out_hex, size_t out_len) {
  if (!path || !out_hex || out_len < 65) return -1;
  out_hex[0] = '\0';
  FILE *fp = fopen(path, "rb");
  if (!fp) return -1;

#if defined(__SWITCH__)
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  mbedtls_sha256_starts(&ctx, 0);
  unsigned char buf[8192];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
    mbedtls_sha256_update(&ctx, buf, n);
  }
  fclose(fp);
  unsigned char digest[32];
  mbedtls_sha256_finish(&ctx, digest);
  mbedtls_sha256_free(&ctx);
  for (int i = 0; i < 32; i++) snprintf(out_hex + i * 2, out_len - (size_t)(i * 2), "%02x", digest[i]);
  return 0;
#else
  /* Host: shell out to shasum/sha256sum for the host test path if needed.
   * Protocol host tests do not call this; return not-implemented. */
  fclose(fp);
  (void)out_len;
  return -1;
#endif
}

static int copy_file(const char *from, const char *to) {
  FILE *in = fopen(from, "rb");
  if (!in) return -1;
  FILE *out = fopen(to, "wb");
  if (!out) {
    fclose(in);
    return -1;
  }
  char buf[8192];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
    if (fwrite(buf, 1, n, out) != n) {
      fclose(in);
      fclose(out);
      return -1;
    }
  }
  fclose(in);
  fclose(out);
  return 0;
}

int ota_fs_atomic_replace_game(const char *install_dir, const char *verified_game_nro,
                               char *err, size_t err_len) {
  return ota_fs_atomic_replace_nro(install_dir, OTA_GAME_NRO_NAME, verified_game_nro, err,
                                   err_len);
}

int ota_fs_atomic_replace_nro(const char *install_dir, const char *nro_name,
                              const char *verified_nro, char *err, size_t err_len) {
  if (!nro_name || !*nro_name || !verified_nro || !*verified_nro) {
    if (err && err_len) snprintf(err, err_len, "missing nro paths");
    return -1;
  }
  char dest[240];
  char part[256];
  snprintf(dest, sizeof(dest), "%s/%s", install_dir ? install_dir : OTA_INSTALL_DIR, nro_name);
  snprintf(part, sizeof(part), "%s.part", dest);
  if (copy_file(verified_nro, part) != 0) {
    if (err && err_len) snprintf(err, err_len, "copy to .part failed (%s)", nro_name);
    return -1;
  }
  /* sdmc/FAT (Switch) and Windows do not replace an existing dest on rename. */
  remove(dest);
  if (rename(part, dest) != 0) {
    if (err && err_len) snprintf(err, err_len, "rename .part -> %s failed", nro_name);
    remove(part);
    return -1;
  }
  return 0;
}

int ota_fs_stage_launcher_bootstrap(const char *install_dir, const char *verified_launcher,
                                    char *bootstrap_out, size_t bootstrap_out_len, char *err,
                                    size_t err_len) {
  if (!verified_launcher || !*verified_launcher) {
    if (err && err_len) snprintf(err, err_len, "missing staged launcher path");
    return -1;
  }
  if (!bootstrap_out || bootstrap_out_len == 0) {
    if (err && err_len) snprintf(err, err_len, "missing bootstrap output buffer");
    return -1;
  }
  bootstrap_out[0] = '\0';

  const char *base = install_dir ? install_dir : OTA_INSTALL_DIR;
  char staged[256];
  char bootstrap[256];
  char updates[192];
  snprintf(staged, sizeof(staged), "%s/%s%s", base, OTA_LAUNCHER_NRO_NAME,
           OTA_LAUNCHER_STAGED_SUFFIX);
  snprintf(updates, sizeof(updates), "%s/updates", base);
  snprintf(bootstrap, sizeof(bootstrap), "%s/updates/%s", base, OTA_BOOTSTRAP_SD_NAME);

  remove(staged);
  if (copy_file(verified_launcher, staged) != 0) {
    if (err && err_len) snprintf(err, err_len, "stage launcher failed");
    return -1;
  }

#if defined(__SWITCH__)
  mkdir(updates, 0755);
#endif
  if (copy_file(OTA_BOOTSTRAP_ROMFS, bootstrap) != 0) {
    remove(staged);
    if (err && err_len) snprintf(err, err_len, "extract bootstrap failed");
    return -1;
  }

  snprintf(bootstrap_out, bootstrap_out_len, "%s", bootstrap);
  return 0;
}

int ota_fs_handoff_to_game(const char *game_nro_path, char *err, size_t err_len) {
  if (!game_nro_path || !*game_nro_path) {
    if (err && err_len) snprintf(err, err_len, "missing game path");
    return -1;
  }
#if defined(__SWITCH__)
  /* argv for next load: empty args string is fine */
  Result rc = envSetNextLoad(game_nro_path, game_nro_path);
  if (R_FAILED(rc)) {
    if (err && err_len) snprintf(err, err_len, "envSetNextLoad failed: 0x%x", rc);
    return -1;
  }
  return 0;
#else
  if (err && err_len)
    snprintf(err, err_len, "handoff stub (host): would envSetNextLoad %s", game_nro_path);
  return 0; /* host stub succeeds for flow tests */
#endif
}
