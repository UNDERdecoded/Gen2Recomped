#include "ota_protocol.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int major;
  int minor;
  int patch;
  int ok;
} semver_t;

static void set_reason(char *buf, size_t n, const char *r) {
  if (!buf || n == 0) return;
  snprintf(buf, n, "%s", r ? r : "");
}

static int parse_semver(const char *s, semver_t *out) {
  memset(out, 0, sizeof(*out));
  if (!s || !*s) return 0;
  if (s[0] == 'v' || s[0] == 'V') s++;
  int maj = 0, min = 0, pat = 0;
  char trail = 0;
  if (sscanf(s, "%d.%d.%d%c", &maj, &min, &pat, &trail) != 3) return 0;
  if (maj < 0 || min < 0 || pat < 0) return 0;
  out->major = maj;
  out->minor = min;
  out->patch = pat;
  out->ok = 1;
  return 1;
}

int ota_compare_semver(const char *a, const char *b) {
  semver_t pa, pb;
  int oa = parse_semver(a, &pa);
  int ob = parse_semver(b, &pb);
  if (!oa && !ob) return 0;
  if (!oa) return -1;
  if (!ob) return 1;
  if (pa.major != pb.major) return pa.major < pb.major ? -1 : 1;
  if (pa.minor != pb.minor) return pa.minor < pb.minor ? -1 : 1;
  if (pa.patch != pb.patch) return pa.patch < pb.patch ? -1 : 1;
  return 0;
}

/* Unified SD/OTA asset: Gen2Recomped-X.Y.Z-switch.zip.
 *
 * The prefix and its length live together deliberately.  Both were spelled
 * out separately when this asset was called gen1recomp-X.Y.Z-switch.zip, and
 * the two disagreed the moment the name changed: an 11-byte compare against a
 * 13-byte prefix still passed (it only reached "Gen2Recompe"), and then
 * sscanf started reading the version out of "d-0.8.0-..." and failed, so the
 * launcher rejected every release it was looking for. */
static const char OTA_ASSET_PREFIX[] = "Gen2Recomped-";
#define OTA_ASSET_PREFIX_LEN (sizeof(OTA_ASSET_PREFIX) - 1)

int ota_is_ota_asset_name(const char *name) {
  int maj = 0, min = 0, pat = 0;
  if (!name) return 0;
  size_t len = strlen(name);
  const char *suffix = "-switch.zip";
  size_t slen = strlen(suffix);
  if (len <= slen) return 0;
  if (strcmp(name + len - slen, suffix) != 0) return 0;
  if (strncmp(name, OTA_ASSET_PREFIX, OTA_ASSET_PREFIX_LEN) != 0) return 0;
  if (sscanf(name + OTA_ASSET_PREFIX_LEN, "%d.%d.%d", &maj, &min, &pat) != 3) return 0;
  char rebuilt[128];
  snprintf(rebuilt, sizeof(rebuilt), "%s%d.%d.%d%s",
           OTA_ASSET_PREFIX, maj, min, pat, suffix);
  return strcmp(name, rebuilt) == 0;
}

int ota_version_from_ota_asset(const char *name, char *out, size_t out_len) {
  int maj = 0, min = 0, pat = 0;
  if (!out || out_len == 0) return 0;
  out[0] = '\0';
  if (!ota_is_ota_asset_name(name)) return 0;
  if (sscanf(name + OTA_ASSET_PREFIX_LEN, "%d.%d.%d", &maj, &min, &pat) != 3) return 0;
  snprintf(out, out_len, "%d.%d.%d", maj, min, pat);
  return 1;
}

static const char *find_json_string(const char *json, const char *key, char *out, size_t out_len) {
  char pattern[128];
  snprintf(pattern, sizeof(pattern), "\"%s\"", key);
  const char *p = strstr(json, pattern);
  if (!p) return NULL;
  p = strchr(p + strlen(pattern), ':');
  if (!p) return NULL;
  p++;
  while (*p && isspace((unsigned char)*p)) p++;
  if (*p != '"') return NULL;
  p++;
  size_t i = 0;
  while (*p && *p != '"' && i + 1 < out_len) {
    if (*p == '\\' && p[1]) {
      p++;
      out[i++] = *p++;
      continue;
    }
    out[i++] = *p++;
  }
  out[i] = '\0';
  return out;
}

/* Opening { of the JSON object that contains pos (walk backward). */
static const char *find_json_object_start(const char *pos, const char *json_start) {
  if (!pos || !json_start || pos < json_start) return NULL;
  int depth = 0;
  const char *p = pos;
  while (p >= json_start) {
    if (*p == '}') depth++;
    else if (*p == '{') {
      if (depth == 0) return p;
      depth--;
    }
    p--;
  }
  return NULL;
}

/* Pointer just past the closing } of the object that starts at object_start. */
static const char *find_json_object_end(const char *object_start) {
  if (!object_start || *object_start != '{') return NULL;
  int depth = 1;
  const char *p = object_start + 1;
  while (*p) {
    if (*p == '{') depth++;
    else if (*p == '}') {
      depth--;
      if (depth == 0) return p + 1;
    }
    p++;
  }
  return NULL;
}

int ota_parse_release(const char *json_text, ota_release_t *out) {
  memset(out, 0, sizeof(*out));
  if (!json_text || !*json_text) {
    set_reason(out->reason, sizeof(out->reason), "empty_json");
    return 0;
  }
  if (!find_json_string(json_text, "tag_name", out->tag, sizeof(out->tag))) {
    set_reason(out->reason, sizeof(out->reason), "missing_tag");
    return 0;
  }
  semver_t sv;
  if (!parse_semver(out->tag, &sv)) {
    set_reason(out->reason, sizeof(out->reason), "bad_tag");
    return 0;
  }
  snprintf(out->version, sizeof(out->version), "%d.%d.%d", sv.major, sv.minor, sv.patch);

  /* Scan for OTA asset name then browser_download_url inside the same asset object. */
  const char *cursor = json_text;
  while ((cursor = strstr(cursor, "\"name\"")) != NULL) {
    char name[128];
    if (!find_json_string(cursor, "name", name, sizeof(name))) {
      cursor += 6;
      continue;
    }
    if (!ota_is_ota_asset_name(name)) {
      cursor += 6;
      continue;
    }
    const char *asset_start = find_json_object_start(cursor, json_text);
    const char *asset_end =
        asset_start ? find_json_object_end(asset_start) : NULL;
    if (!asset_start || !asset_end || asset_end <= cursor) {
      cursor += 6;
      continue;
    }
    char url[512];
    const char *u = NULL;
    const char *scan = cursor;
    while (scan < asset_end &&
           (scan = strstr(scan, "\"browser_download_url\"")) != NULL && scan < asset_end) {
      if (find_json_string(scan, "browser_download_url", url, sizeof(url))) {
        u = url;
        break;
      }
      scan += 21;
    }
    if (!u || !*u) {
      cursor += 6;
      continue;
    }
    snprintf(out->asset_name, sizeof(out->asset_name), "%s", name);
    snprintf(out->download_url, sizeof(out->download_url), "%s", u);
    out->ok = 1;
    return 1;
  }
  set_reason(out->reason, sizeof(out->reason), "missing_ota_asset");
  return 0;
}

void ota_decide_update(const char *installed_version, const ota_release_t *release,
                       ota_decision_t *out) {
  memset(out, 0, sizeof(*out));
  semver_t inst;
  if (!parse_semver(installed_version, &inst)) {
    snprintf(out->status, sizeof(out->status), "error");
    set_reason(out->reason, sizeof(out->reason), "bad_installed_version");
    return;
  }
  if (!release || !release->ok) {
    snprintf(out->status, sizeof(out->status), "error");
    set_reason(out->reason, sizeof(out->reason), "bad_release");
    return;
  }
  if (ota_compare_semver(release->version, installed_version) <= 0) {
    snprintf(out->status, sizeof(out->status), "uptodate");
    snprintf(out->version, sizeof(out->version), "%s", installed_version);
    return;
  }
  snprintf(out->status, sizeof(out->status), "available");
  snprintf(out->version, sizeof(out->version), "%s", release->version);
  snprintf(out->asset_name, sizeof(out->asset_name), "%s", release->asset_name);
  snprintf(out->download_url, sizeof(out->download_url), "%s", release->download_url);
}

int ota_lookup_sum(const char *sums_text, const char *asset_name, char *out_hex, size_t out_len) {
  if (out_hex && out_len) out_hex[0] = '\0';
  if (!sums_text || !asset_name || !out_hex || out_len < 65) return 0;
  const char *p = sums_text;
  while (*p) {
    char hex[96];
    char name[256];
    int n = 0;
    if (sscanf(p, "%95s %255s%n", hex, name, &n) >= 2 && n > 0) {
      const char *nm = name;
      if (nm[0] == '*') nm++;
      if (strncmp(nm, "./", 2) == 0) nm += 2;
      if (strcmp(nm, asset_name) == 0) {
        /* normalize hex to lowercase */
        size_t i;
        for (i = 0; hex[i] && i + 1 < out_len; i++)
          out_hex[i] = (char)tolower((unsigned char)hex[i]);
        out_hex[i] = '\0';
        return 1;
      }
      p += n;
      while (*p && *p != '\n') p++;
      if (*p == '\n') p++;
      continue;
    }
    while (*p && *p != '\n') p++;
    if (*p == '\n') p++;
  }
  return 0;
}

void ota_verify_sha256(const char *asset_name, const char *actual_hex, const char *sums_text,
                       ota_verify_t *out) {
  memset(out, 0, sizeof(*out));
  if (!asset_name || !*asset_name) {
    set_reason(out->reason, sizeof(out->reason), "bad_asset_name");
    return;
  }
  if (!sums_text) {
    set_reason(out->reason, sizeof(out->reason), "missing_sums");
    return;
  }
  char expected[96];
  if (!ota_lookup_sum(sums_text, asset_name, expected, sizeof(expected))) {
    set_reason(out->reason, sizeof(out->reason), "sum_not_found");
    return;
  }
  if (!actual_hex || !*actual_hex) {
    set_reason(out->reason, sizeof(out->reason), "missing_actual_hash");
    return;
  }
  char actual[96];
  size_t i;
  for (i = 0; actual_hex[i] && i + 1 < sizeof(actual); i++)
    actual[i] = (char)tolower((unsigned char)actual_hex[i]);
  actual[i] = '\0';
  if (strcmp(actual, expected) != 0) {
    set_reason(out->reason, sizeof(out->reason), "hash_mismatch");
    return;
  }
  out->ok = 1;
}

void ota_plan_atomic_apply(const char *install_dir, const char *verified_temp,
                           ota_apply_plan_t *out) {
  memset(out, 0, sizeof(*out));
  if (!install_dir || !*install_dir) install_dir = OTA_INSTALL_DIR;
  if (!verified_temp) verified_temp = "";
  snprintf(out->game_nro, sizeof(out->game_nro), "%s/%s", install_dir, OTA_GAME_NRO_NAME);
  snprintf(out->part_path, sizeof(out->part_path), "%s.part", out->game_nro);
  snprintf(out->launcher_nro, sizeof(out->launcher_nro), "%s/%s", install_dir,
           OTA_LAUNCHER_NRO_NAME);
  snprintf(out->launcher_part, sizeof(out->launcher_part), "%s.part", out->launcher_nro);
  snprintf(out->next_load, sizeof(out->next_load), "%s", out->game_nro);
  /* verified_temp is the game NRO; launcher replace uses a sibling verified path */
  snprintf(out->steps[0], sizeof(out->steps[0]), "copy_to_part:%s->%s", verified_temp,
           out->part_path);
  snprintf(out->steps[1], sizeof(out->steps[1]), "rename:%s->%s", out->part_path, out->game_nro);
  snprintf(out->steps[2], sizeof(out->steps[2]), "copy_to_part:launcher->%s", out->launcher_part);
  snprintf(out->steps[3], sizeof(out->steps[3]), "rename:%s->%s", out->launcher_part,
           out->launcher_nro);
  snprintf(out->steps[4], sizeof(out->steps[4]), "env_set_next_load:%s", out->game_nro);
  snprintf(out->preserve, sizeof(out->preserve), "%s/%s", install_dir, OTA_SAVE_DIR_NAME);
  snprintf(out->forbidden_delete, sizeof(out->forbidden_delete), "delete:%s/%s", install_dir,
           OTA_SAVE_DIR_NAME);
  snprintf(out->forbidden_direct, sizeof(out->forbidden_direct), "write_direct:%s", out->game_nro);
}

void ota_offline_policy(double elapsed_sec, const ota_offline_events_t *events, ota_offline_t *out) {
  memset(out, 0, sizeof(*out));
  ota_offline_events_t ev = {0, -1, 0};
  if (events) ev = *events;
  if (ev.user_skip) {
    snprintf(out->action, sizeof(out->action), "play_installed");
    set_reason(out->reason, sizeof(out->reason), "user_skip");
    snprintf(out->message, sizeof(out->message), "update skipped");
    return;
  }
  if (ev.api_error || ev.network_ok == 0) {
    snprintf(out->action, sizeof(out->action), "play_installed");
    set_reason(out->reason, sizeof(out->reason), "offline_or_error");
    snprintf(out->message, sizeof(out->message),
             "offline or update check failed — play installed version");
    return;
  }
  if (elapsed_sec >= (double)OTA_CHECK_TIMEOUT_SEC) {
    snprintf(out->action, sizeof(out->action), "play_installed");
    set_reason(out->reason, sizeof(out->reason), "timeout");
    snprintf(out->message, sizeof(out->message), "update check timed out after %ds",
             OTA_CHECK_TIMEOUT_SEC);
    return;
  }
  snprintf(out->action, sizeof(out->action), "keep_checking");
  set_reason(out->reason, sizeof(out->reason), "in_flight");
}
