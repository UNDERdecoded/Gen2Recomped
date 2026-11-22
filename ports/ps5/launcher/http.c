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
    /* curl -L, as on desktop. Only web schemes, on the first URL and on every
     * hop: libcurl would otherwise also speak file://, ftp://, smb://... to
     * whatever a feed or a redirect names. */
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    /* curl -f: stop on an error status rather than saving the error page. */
    curl_easy_setopt(curl, CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 300L);
    /* Called from love.thread workers: no SIGALRM-based timeouts and no
     * SIGPIPE on a dropped connection, neither of which a thread can own. */
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    /* A resolver that never answers (a console whose DNS is pointed at a
     * blackhole to keep it off Sony's servers) times out at the connect limit
     * above, but curl_easy_cleanup would then wait for the lookup thread to
     * give up on its own: measured 30 s instead of 15 against a 30 s resolver
     * timeout. Quick exit leaves that thread to finish by itself -- it holds
     * a few hundred bytes until it does -- so the caller, often the main
     * thread, is back at the limit. */
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

    CURLcode rc = curl_easy_perform(curl);
    long status = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    /* fclose flushes the last buffer: a full disk shows up here, not above. */
    int closed = fclose(out);
    int ok = 0;
    if (rc == CURLE_HTTP_RETURNED_ERROR || (rc == CURLE_OK && status >= 400)) {
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
