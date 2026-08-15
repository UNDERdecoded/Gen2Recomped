#ifndef GEN1_OTA_NET_H
#define GEN1_OTA_NET_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* fraction is 0..1 when Content-Length is known, else -1 for indeterminate. */
typedef void (*ota_net_progress_fn)(void *userdata, double fraction);

/* Mount romfs (CA bundle) and init libcurl. Call before any HTTPS download. */
int ota_net_init(void);
void ota_net_shutdown(void);

/* Download URL into memory buffer (caller frees *out). Returns 0 on success. */
int ota_net_download_buffer(const char *url, long timeout_ms, char **out, size_t *out_len,
                            char *err, size_t err_len);

/* Download URL to a filesystem path. progress may be NULL. Returns 0 on success. */
int ota_net_download_file(const char *url, const char *path, long timeout_ms, char *err,
                          size_t err_len, ota_net_progress_fn progress, void *progress_ud);

#ifdef __cplusplus
}
#endif

#endif
