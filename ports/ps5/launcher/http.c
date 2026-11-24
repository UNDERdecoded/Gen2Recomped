/* Gen2Recomped PS5: love.system.httpDownload, the game's HTTPS client.
 *
 * The game fetches everything remote (mod index and mod zips, launcher news,
 * the update notice, the translation glossary) through
 * src/core/HostShell.lua, which shells out to curl on the desktops and calls
 * love.system.httpDownload(url, absPath, userAgent, accept) where there is no
 * shell. A title cannot spawn processes, so this is that call for the PS5:
 * PacBrew's static libcurl (OpenSSL), wired into LOVE's love.system table by
 * ports/ps5/love/0003-love-system-httpdownload.patch. Being in love.system,
 * it exists in every Lua state, love.thread workers included.
 *
 * Plain C with no LOVE or PS5 headers, so the same file builds on Linux
 * against the system libcurl for a host-side test (the PS5 build passes
 * -DG2R_HTTP_CA_EMBEDDED with the generated CA bundle).
 *
 * Contract, the one HostShell.httpDownload has with curl -fsSL on desktop:
 *   - blocking GET, redirects followed (GitHub release assets redirect to
 *     objects.githubusercontent.com);
 *   - an HTTP status >= 400 fails with "HTTP <code>";
 *   - 15 s to connect, 300 s for the whole transfer;
 *   - the body goes to <absPath>.part and is renamed over absPath only when
 *     the transfer finished, so absPath is never a truncated file.
 * Returns 1, or 0 with the reason in `why`. Safe to call from several threads
 * at once: every call has its own easy handle, and the global init runs once. */
#include <curl/curl.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <time.h>

/* Redirect hops followed before giving up, as curl -L's default 50 is far
 * more than GitHub's one hop to objects.githubusercontent.com needs. */
#define G2R_HTTP_MAX_HOPS 10

#ifdef G2R_HTTP_CA_EMBEDDED
/* Mozilla's CA bundle as curl.se publishes it, pinned by sha256 in
 * scripts/ps5/deps.sh and compiled in by scripts/ps5/build_runtime.sh.
 *
 * Embedded rather than shipped as a file next to eboot.bin: PacBrew's libcurl
 * looks for /user/homebrew/etc/ca-bundle.crt, which a player's console does
 * not have, and a separate file is one more thing an FTP copy can leave out
 * or leave stale. Inside the executable it is always the bundle the build
 * pinned, and no path on the console matters. */
extern const unsigned char g2r_cacert[];
extern const size_t g2r_cacert_size;
#endif

static pthread_once_t g2r_http_once = PTHREAD_ONCE_INIT;
static CURLcode g2r_http_init_result = CURLE_FAILED_INIT;

/* curl_global_init is not thread-safe and the first download can come from
 * any love.thread; pthread_once makes the first caller do it. Never cleaned
 * up: the title is closed by the system, not by returning from main. */
static void g2r_http_global_init(void)
{
    g2r_http_init_result = curl_global_init(CURL_GLOBAL_DEFAULT);
}

static void g2r_http_say(const char *url, const char *why)
{
    /* stdout is <data root>/love.log (ports/ps5/launcher/main.cpp): the one
     * place a failed download on the console can be read back from. */
    printf("httpDownload: %s: %s\n", url, why);
    fflush(stdout);
}

static size_t g2r_http_write(char *data, size_t size, size_t count, void *user)
{
    return fwrite(data, size, count, (FILE *)user) * size;
}

/* Look the URL's host up here, on the calling thread, and hand curl the
 * answer as a CURLOPT_RESOLVE entry ("host:port:address").
 *
 * libcurl's own lookup runs getaddrinfo on a helper thread it starts per
 * request, and on the console that start fails ("getaddrinfo() thread failed
 * to start"), so every download failed before it connected. With the entry in
 * place curl finds the host in its DNS cache and never starts the helper. The
 * caller is a love.thread worker or the launcher's own fetch, so a blocking
 * lookup here costs nothing curl's would not have.
 *
 * Returns 1 with *out set to the list to free after the transfer (NULL for a
 * literal IP address, which needs no entry), or 0 with `why` filled. */
static int g2r_http_resolve(const char *url, struct curl_slist **out, char *why, size_t why_size)
{
    *out = NULL;
    CURLU *u = curl_url();
    if (u == NULL) {
        snprintf(why, why_size, "out of memory");
        return 0;
    }
    char *host = NULL, *port = NULL;
    CURLUcode uc = curl_url_set(u, CURLUPART_URL, url, 0);
    if (uc == CURLUE_OK)
        uc = curl_url_get(u, CURLUPART_HOST, &host, 0);
    if (uc == CURLUE_OK)
        uc = curl_url_get(u, CURLUPART_PORT, &port, CURLU_DEFAULT_PORT);
    curl_url_cleanup(u);
    if (uc != CURLUE_OK || host == NULL || port == NULL) {
        snprintf(why, why_size, "bad url: %s", curl_url_strerror(uc));
        curl_free(host);
        curl_free(port);
        return 0;
    }

    struct curl_slist *list = NULL;
    int ok = 0;
    struct in_addr literal;
    if (host[0] == '[' || inet_pton(AF_INET, host, &literal) == 1) {
        /* an address already: nothing to look up */
        ok = 1;
    } else {
        struct addrinfo hints, *res = NULL;
        memset(&hints, 0, sizeof hints);
        /* IPv4 only, as CURLOPT_IPRESOLVE below asks: the payload SDK's
         * resolver refuses AF_INET6 outright. */
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        int gai = getaddrinfo(host, port, &hints, &res);
        if (gai != 0 || res == NULL) {
            snprintf(why, why_size, "could not resolve %s (%s)", host,
                     gai != 0 ? gai_strerror(gai) : "no address");
        } else {
            char entry[512];
            size_t at = (size_t)snprintf(entry, sizeof entry, "%s:%s:", host, port);
            int first = 1;
            /* every address the resolver gave, so curl can fall through them
             * as it would after its own lookup */
            for (struct addrinfo *ai = res; ai != NULL && at < sizeof entry - 20; ai = ai->ai_next) {
                if (ai->ai_family != AF_INET)
                    continue;
                char ip[INET_ADDRSTRLEN];
                const struct sockaddr_in *sin = (const struct sockaddr_in *)ai->ai_addr;
                if (inet_ntop(AF_INET, &sin->sin_addr, ip, sizeof ip) == NULL)
                    continue;
                at += (size_t)snprintf(entry + at, sizeof entry - at, "%s%s", first ? "" : ",", ip);
                first = 0;
            }
            freeaddrinfo(res);
            if (first) {
                snprintf(why, why_size, "could not resolve %s (no IPv4 address)", host);
            } else {
                list = curl_slist_append(NULL, entry);
                if (list != NULL)
                    ok = 1;
                else
                    snprintf(why, why_size, "out of memory");
            }
        }
    }
    curl_free(host);
    curl_free(port);
    *out = list;
    return ok;
}

int g2r_http_download(const char *url, const char *dest, const char *user_agent,
                      const char *accept, char *why, size_t why_size)
{
    if (why_size > 0)
        why[0] = 0;
    if (url == NULL || *url == 0) {
        snprintf(why, why_size, "missing url");
        return 0;
    }
    /* A relative path is EINVAL in a title (it has no working directory
     * worth the name); HostShell always passes <save directory>/<name>. */
    if (dest == NULL || dest[0] != '/') {
        snprintf(why, why_size, "the destination must be an absolute path");
        return 0;
    }

    pthread_once(&g2r_http_once, g2r_http_global_init);
    if (g2r_http_init_result != CURLE_OK) {
        snprintf(why, why_size, "curl_global_init: %s", curl_easy_strerror(g2r_http_init_result));
        g2r_http_say(url, why);
        return 0;
    }

    size_t dest_len = strlen(dest);
    char *part = malloc(dest_len + sizeof(".part"));
    if (part == NULL) {
        snprintf(why, why_size, "out of memory");
        return 0;
    }
    memcpy(part, dest, dest_len);
    memcpy(part + dest_len, ".part", sizeof(".part"));

    FILE *out = fopen(part, "wb");
    if (out == NULL) {
        snprintf(why, why_size, "cannot write %s: %s", part, strerror(errno));
        g2r_http_say(url, why);
        free(part);
        return 0;
    }

    CURL *curl = curl_easy_init();
    if (curl == NULL) {
        fclose(out);
        remove(part);
        free(part);
        snprintf(why, why_size, "curl_easy_init failed");
        g2r_http_say(url, why);
        return 0;
    }

    char error[CURL_ERROR_SIZE];
    error[0] = 0;
    struct curl_slist *headers = NULL;
    if (accept != NULL && *accept != 0) {
        size_t n = strlen(accept) + sizeof("Accept: ");
        char *line = malloc(n);
        if (line != NULL) {
            snprintf(line, n, "Accept: %s", accept);
            headers = curl_slist_append(headers, line);
            free(line);
        }
    }

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, error);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, g2r_http_write);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, out);
    curl_easy_setopt(curl, CURLOPT_USERAGENT,
                     (user_agent != NULL && *user_agent != 0) ? user_agent : "gen1recomp");
    if (headers != NULL)
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    /* curl -L, as on desktop, but hop by hop below rather than with
     * CURLOPT_FOLLOWLOCATION: every host has to go through g2r_http_resolve
     * first, and a redirect names a new one. Only web schemes, on the first
     * URL and on every hop: libcurl would otherwise also speak file://,
     * ftp://, smb://... to whatever a feed or a redirect names. */
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
    /* curl -f: stop on an error status rather than saving the error page. */
    curl_easy_setopt(curl, CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 300L);
    /* Called from love.thread workers: no SIGALRM-based timeouts and no
     * SIGPIPE on a dropped connection, neither of which a thread can own. */
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    /* Kept for a host build whose libcurl still starts its own lookup thread
     * (a literal-address URL, or a resolve entry curl ignores): cleanup then
     * does not wait for that thread. On the console the lookup is
     * g2r_http_resolve's, which blocks for the resolver's own timeout when
     * DNS never answers (a console pointed at a blackhole to keep it off
     * Sony's servers) -- on a worker thread, where nothing waits on it. */
    curl_easy_setopt(curl, CURLOPT_QUICK_EXIT, 1L);
#ifdef __PROSPERO__
    /* The payload SDK's getaddrinfo (libc.a, over sceNetResolverStartNtoa)
     * answers IPv4 only and refuses an AF_INET6 request outright; asking for
     * v4 keeps curl from spending a lookup on a family it cannot get. */
    curl_easy_setopt(curl, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4);
#endif
    /* gzip/zstd for the JSON feeds, whatever this libcurl was built with. */
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
    /* Peer and host verification stay on (libcurl's defaults, spelled out so
     * nobody turns them off to "fix" a console that lacks the CA file). */
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
#ifdef G2R_HTTP_CA_EMBEDDED
    /* Trust exactly the embedded bundle. The compiled-in CA file and path
     * point into /user/homebrew, which is not there on a player's console;
     * clearing them keeps a stray file from widening the trust set. */
    curl_easy_setopt(curl, CURLOPT_CAINFO, NULL);
    curl_easy_setopt(curl, CURLOPT_CAPATH, NULL);
    struct curl_blob ca = {(void *)g2r_cacert, g2r_cacert_size, CURL_BLOB_NOCOPY};
    curl_easy_setopt(curl, CURLOPT_CAINFO_BLOB, &ca);
#endif

    CURLcode rc = CURLE_OK;
    long status = 0;
    int resolved = 1;
    char *hop = strdup(url);
    struct curl_slist *resolves[G2R_HTTP_MAX_HOPS + 1] = {0};
    for (int n = 0; hop != NULL; n++) {
        if (n > G2R_HTTP_MAX_HOPS) {
            rc = CURLE_TOO_MANY_REDIRECTS;
            break;
        }
        struct timespec t0, t1, t2;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        if (!g2r_http_resolve(hop, &resolves[n], why, why_size)) {
            resolved = 0;
            break;
        }
        clock_gettime(CLOCK_MONOTONIC, &t1);
        curl_easy_setopt(curl, CURLOPT_URL, hop);
        if (resolves[n] != NULL)
            curl_easy_setopt(curl, CURLOPT_RESOLVE, resolves[n]);
        rc = curl_easy_perform(curl);
        clock_gettime(CLOCK_MONOTONIC, &t2);
        status = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
        /* A slow hop says where its time went (measured on the console: a
         * GitHub API call is ~20 ms lookup, ~90 ms TLS, ~0.3 s in all), so a
         * stalled launcher can be told apart from a stalled network. Quiet
         * otherwise: one line per download would bury the log. */
        long dns_ms = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000;
        long perf_ms = (t2.tv_sec - t1.tv_sec) * 1000 + (t2.tv_nsec - t1.tv_nsec) / 1000000;
        if (dns_ms + perf_ms > 3000) {
            curl_off_t con = 0, tls = 0, ttfb = 0;
            curl_easy_getinfo(curl, CURLINFO_CONNECT_TIME_T, &con);
            curl_easy_getinfo(curl, CURLINFO_APPCONNECT_TIME_T, &tls);
            curl_easy_getinfo(curl, CURLINFO_STARTTRANSFER_TIME_T, &ttfb);
            printf("httpDownload: slow %s: lookup %ld ms, connect %ld ms, tls %ld ms, "
                   "first byte %ld ms, transfer %ld ms\n",
                   hop, dns_ms, (long)(con / 1000), (long)(tls / 1000), (long)(ttfb / 1000), perf_ms);
            fflush(stdout);
        }
        char *next = NULL;
        if (rc == CURLE_OK && status >= 300 && status < 400)
            curl_easy_getinfo(curl, CURLINFO_REDIRECT_URL, &next);
        free(hop);
        hop = NULL;
        if (next != NULL) {
            /* the redirect's own body is not the file: start it over */
            hop = strdup(next);
            fflush(out);
            if (freopen(part, "wb", out) == NULL) {
                out = NULL;
                snprintf(why, why_size, "cannot write %s: %s", part, strerror(errno));
                resolved = 0;
                free(hop);
                hop = NULL;
                break;
            }
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, out);
        }
    }
    free(hop);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    for (int n = 0; n <= G2R_HTTP_MAX_HOPS; n++)
        curl_slist_free_all(resolves[n]);

    /* fclose flushes the last buffer: a full disk shows up here, not above. */
    int closed = out != NULL ? fclose(out) : 0;
    int ok = 0;
    if (!resolved) {
        /* `why` already says what */
    } else if (rc == CURLE_HTTP_RETURNED_ERROR || (rc == CURLE_OK && status >= 400)) {
        snprintf(why, why_size, "HTTP %ld", status);
    } else if (rc != CURLE_OK) {
        snprintf(why, why_size, "%s", error[0] != 0 ? error : curl_easy_strerror(rc));
    } else if (closed != 0) {
        snprintf(why, why_size, "cannot write %s: %s", part, strerror(errno));
    } else if (rename(part, dest) != 0) {
        /* rename() replaces an existing file; if this filesystem refuses,
         * drop the old copy and try once more. */
        remove(dest);
        if (rename(part, dest) != 0)
            snprintf(why, why_size, "cannot move %s into place: %s", part, strerror(errno));
        else
            ok = 1;
    } else {
        ok = 1;
    }

    if (!ok) {
        remove(part);
        g2r_http_say(url, why);
    }
    free(part);
    return ok;
}
