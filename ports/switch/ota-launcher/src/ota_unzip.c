#include "ota_unzip.h"

#include <stdio.h>
#include <string.h>

#if defined(__SWITCH__)
#include <fcntl.h>
#include <zzip/zzip.h>
#endif

#if defined(__SWITCH__)
static int extract_member(ZZIP_DIR *dir, const char *member, const char *dest_path, char *err,
                          size_t err_len) {
  ZZIP_FILE *zf = zzip_file_open(dir, member, O_RDONLY);
  if (!zf) return 1; /* not found / cannot open */

  FILE *out = fopen(dest_path, "wb");
  if (!out) {
    zzip_file_close(zf);
    if (err && err_len) snprintf(err, err_len, "fopen dest failed: %s", dest_path);
    return -1;
  }

  char buf[8192];
  zzip_ssize_t n;
  while ((n = zzip_file_read(zf, buf, sizeof(buf))) > 0) {
    if ((zzip_ssize_t)fwrite(buf, 1, (size_t)n, out) != n) {
      fclose(out);
      zzip_file_close(zf);
      if (err && err_len) snprintf(err, err_len, "fwrite failed");
      return -1;
    }
  }
  fclose(out);
  zzip_file_close(zf);
  if (n < 0) {
    if (err && err_len) snprintf(err, err_len, "zzip_file_read failed");
    return -1;
  }
  return 0;
}
#endif

int ota_unzip_extract_file(const char *zip_path, const char *member_name, const char *dest_path,
                           char *err, size_t err_len) {
  if (!zip_path || !member_name || !dest_path) {
    if (err && err_len) snprintf(err, err_len, "bad args");
    return -1;
  }
#if defined(__SWITCH__)
  zzip_error_t zerr = ZZIP_NO_ERROR;
  ZZIP_DIR *dir = zzip_dir_open(zip_path, &zerr);
  if (!dir) {
    if (err && err_len) snprintf(err, err_len, "zzip_dir_open failed (%d): %s", (int)zerr, zip_path);
    return -1;
  }

  char alt1[192];
  char alt2[192];
  snprintf(alt1, sizeof(alt1), "switch/gen1recomp/%s", member_name);
  snprintf(alt2, sizeof(alt2), "./%s", member_name);

  const char *candidates[] = {member_name, alt1, alt2, NULL};
  int rc = -1;
  if (err && err_len) err[0] = '\0';
  for (int i = 0; candidates[i]; i++) {
    int t = extract_member(dir, candidates[i], dest_path, err, err_len);
    if (t == 0) {
      rc = 0;
      break;
    }
    if (t < 0) {
      rc = -1;
      break;
    }
  }
  if (rc != 0 && err && err_len && !err[0]) {
    snprintf(err, err_len, "member not found in zip: %s", member_name);
  }
  zzip_dir_close(dir);
  return rc;
#else
  (void)zip_path;
  (void)member_name;
  (void)dest_path;
  if (err && err_len) snprintf(err, err_len, "ota_unzip only available on __SWITCH__");
  return -1;
#endif
}
