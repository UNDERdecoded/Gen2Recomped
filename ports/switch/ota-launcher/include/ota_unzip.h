#ifndef GEN1_OTA_UNZIP_H
#define GEN1_OTA_UNZIP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Extract member_name from zip_path into dest_path.
 * Tries exact member_name, then common prefixes (switch/gen1recomp/).
 * Returns 0 on success. */
int ota_unzip_extract_file(const char *zip_path, const char *member_name, const char *dest_path,
                           char *err, size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
