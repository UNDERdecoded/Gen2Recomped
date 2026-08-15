#include "ota_net.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SWITCH__)
#include <curl/curl.h>
#include <switch.h>
#endif

#if defined(__SWITCH__)
#define OTA_CA_BUNDLE "romfs:/cacert.pem"

static int g_net_ready = 0;

static int ota_ca_bundle_ready(void) {
  FILE *f = fopen(OTA_CA_BUNDLE, "rb");
  if (!f) return 0;
  fclose(f);
  return 1;
}

int ota_net_init(void) {
  if (g_net_ready) return 0;
  if (R_FAILED(romfsInit())) return -1;
  if (!ota_ca_bundle_ready()) return -1;
  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) return -1;
  g_net_ready = 1;
  return 0;
}

void ota_net_shutdown(void) {
  if (!g_net_ready) return;
  curl_global_cleanup();
  romfsExit();
  g_net_ready = 0;
}

static void ota_net_configure_tls(CURL *curl) {
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
  curl_easy_setopt(curl, CURLOPT_CAINFO, OTA_CA_BUNDLE);
}

struct mem_buf {
  char *data;
  size_t len;
};

struct file_progress {
  ota_net_progress_fn fn;
  void *userdata;
};

static size_t write_mem(char *ptr, size_t size, size_t nmemb, void *userdata) {
  struct mem_buf *m = (struct mem_buf *)userdata;
  size_t n = size * nmemb;
  char *p = (char *)realloc(m->data, m->len + n + 1);
  if (!p) return 0;
  m->data = p;
  memcpy(m->data + m->len, ptr, n);
  m->len += n;
  m->data[m->len] = '\0';
  return n;
}

static size_t write_file(char *ptr, size_t size, size_t nmemb, void *userdata) {
  return fwrite(ptr, size, nmemb, (FILE *)userdata);
}

static int xfer_progress(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal,
                         curl_off_t ulnow) {
  (void)ultotal;
  (void)ulnow;
  struct file_progress *fp = (struct file_progress *)clientp;
  if (!fp || !fp->fn) return 0;
  if (dltotal > 0) {
    double frac = (double)dlnow / (double)dltotal;
    if (frac < 0.0) frac = 0.0;
    if (frac > 1.0) frac = 1.0;
    fp->fn(fp->userdata, frac);
  } else if (dlnow > 0) {
    fp->fn(fp->userdata, -1.0);
  }
  return 0;
}
#else

int ota_net_init(void) { return 0; }
void ota_net_shutdown(void) {}

#endif

int ota_net_download_buffer(const char *url, long timeout_ms, char **out, size_t *out_len,
                            char *err, size_t err_len) {
  if (out) *out = NULL;
  if (out_len) *out_len = 0;
  if (!url || !out) {
    if (err && err_len) snprintf(err, err_len, "bad args");
    return -1;
  }
#if defined(__SWITCH__)
  CURL *curl = curl_easy_init();
  if (!curl) {
    if (err && err_len) snprintf(err, err_len, "curl_easy_init failed");
    return -1;
  }
  struct mem_buf mem = {0};
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "Gen2Recomped-switch-ota");
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_mem);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &mem);
  ota_net_configure_tls(curl);
  CURLcode rc = curl_easy_perform(curl);
  curl_easy_cleanup(curl);
  if (rc != CURLE_OK) {
    free(mem.data);
    if (err && err_len) snprintf(err, err_len, "%s", curl_easy_strerror(rc));
    return -1;
  }
  *out = mem.data;
  if (out_len) *out_len = mem.len;
  return 0;
#else
  (void)timeout_ms;
  if (err && err_len)
    snprintf(err, err_len, "ota_net_download_buffer only available on __SWITCH__");
  return -1;
#endif
}

int ota_net_download_file(const char *url, const char *path, long timeout_ms, char *err,
                          size_t err_len, ota_net_progress_fn progress, void *progress_ud) {
  if (!url || !path) {
    if (err && err_len) snprintf(err, err_len, "bad args");
    return -1;
  }
#if defined(__SWITCH__)
  FILE *fp = fopen(path, "wb");
  if (!fp) {
    if (err && err_len) snprintf(err, err_len, "fopen failed: %s", path);
    return -1;
  }
  CURL *curl = curl_easy_init();
  if (!curl) {
    fclose(fp);
    if (err && err_len) snprintf(err, err_len, "curl_easy_init failed");
    return -1;
  }
  struct file_progress fp_cb = {progress, progress_ud};
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "Gen2Recomped-switch-ota");
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_file);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, fp);
  ota_net_configure_tls(curl);
  if (progress) {
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, xfer_progress);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &fp_cb);
  }
  CURLcode rc = curl_easy_perform(curl);
  curl_easy_cleanup(curl);
  fclose(fp);
  if (rc != CURLE_OK) {
    if (err && err_len) snprintf(err, err_len, "%s", curl_easy_strerror(rc));
    return -1;
  }
  if (progress) progress(progress_ud, 1.0);
  return 0;
#else
  (void)timeout_ms;
  (void)progress;
  (void)progress_ud;
  if (err && err_len)
    snprintf(err, err_len, "ota_net_download_file only available on __SWITCH__");
  return -1;
#endif
}
