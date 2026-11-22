/* Gen2Recomped PS5: libc functions the title defines itself.
 *
 * A title gets no libScePosixForWebKit and no libkernel_sys, so an import the
 * payload SDK only finds there is a null call at run time.
 * scripts/ps5/check_imports.py lists such imports after linking and fails the
 * build; each one is answered here instead. */
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <pthread.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

void arc4random_buf(void *buffer, size_t length);

/* libc++ (std::random_device) wants it and no Sony module exports it; the
 * payload SDK's arc4random (sysctl KERN_ARND) does the work. */
int getentropy(void *buffer, size_t length)
{
    if (length > 256) {
        errno = EIO;
        return -1;
    }
    arc4random_buf(buffer, length);
    return 0;
}

/* libc++abi's __cxa_thread_atexit (thread_local destructors) calls this when
 * the C library has it; the converter wants every import resolved, and no
 * Sony module has it. Destructors run at thread exit, newest first. */
struct g2r_tls_dtor {
    void (*dtor)(void *);
    void *object;
    struct g2r_tls_dtor *next;
};
static pthread_key_t g2r_tls_key;
static pthread_once_t g2r_tls_once = PTHREAD_ONCE_INIT;

static void g2r_tls_run(void *list)
{
    struct g2r_tls_dtor *node = list;
    while (node != NULL) {
        struct g2r_tls_dtor *next = node->next;
        node->dtor(node->object);
        free(node);
        node = next;
    }
}

static void g2r_tls_init(void)
{
    pthread_key_create(&g2r_tls_key, g2r_tls_run);
}

int __cxa_thread_atexit_impl(void (*dtor)(void *), void *object, void *dso)
{
    (void)dso;
    pthread_once(&g2r_tls_once, g2r_tls_init);
    struct g2r_tls_dtor *node = malloc(sizeof(*node));
    if (node == NULL)
        return -1;
    node->dtor = dtor;
    node->object = object;
    node->next = pthread_getspecific(g2r_tls_key);
    pthread_setspecific(g2r_tls_key, node);
    return 0;
}

/* lstat() in a title fails with EPERM for every path, existing or not
 * (measured on 13.00; stat() works). PhysFS stats with lstat when it creates
 * directories, so LOVE could never set up its save directory. Linked with
 * --wrap=lstat: fall back to stat(), which only differs for symbolic links,
 * and a title's data folders have none. */
int __real_lstat(const char *path, struct stat *st);

int __wrap_lstat(const char *path, struct stat *st)
{
    int rc = __real_lstat(path, st);
    if (rc != 0 && errno == EPERM)
        rc = stat(path, st);
    return rc;
}

/* Close-on-exec. The kernel refuses fcntl(F_SETFD, FD_CLOEXEC) on a socket
 * from a title with EINVAL (measured on 13.00), and libcurl sets it on every
 * socket it opens and gives up on the connection when it fails ("fcntl set
 * CLOEXEC: Invalid argument"), so love.system.httpDownload could never
 * connect. A title never execs, so close-on-exec has nothing to guard
 * against: linked with --wrap=fcntl, a refused F_SETFD is treated as done.
 * Every other command, and every other failure, is passed through as is. */
int __real_fcntl(int fd, int cmd, ...);

int __wrap_fcntl(int fd, int cmd, ...)
{
    va_list ap;
    va_start(ap, cmd);
    /* every fcntl argument is an int or a pointer; as a long it is passed in
     * the same register either way */
    long arg = va_arg(ap, long);
    va_end(ap);
    int saved = errno;
    int rc = __real_fcntl(fd, cmd, arg);
    if (rc == -1 && cmd == F_SETFD && errno == EINVAL) {
        errno = saved;
        return 0;
    }
    return rc;
}

/* Directory listing. In a title, readdir() through the system C library
 * returns no entries under /data (measured on 13.00: PhysFS saw an empty
 * save directory and imports/ folder while stat() found the files in them),
 * so love.filesystem.getDirectoryItems was always empty and the import inbox
 * never found a ROM. The kernel answers getdents() on /data only with a
 * 64 KiB buffer (PS5Homebrew's notes); smaller ones get EINVAL. Linked with
 * --wrap=opendir/readdir/closedir, so PhysFS and everything else use this. */
struct g2r_dir {
    int fd;
    int len;
    int pos;
    char buf[65536] __attribute__((aligned(8)));
};

DIR *__wrap_opendir(const char *path)
{
    int fd = open(path, O_RDONLY | O_DIRECTORY);
    if (fd < 0)
        return NULL;
    struct g2r_dir *d = malloc(sizeof(*d));
    if (d == NULL) {
        close(fd);
        errno = ENOMEM;
        return NULL;
    }
    d->fd = fd;
    d->len = 0;
    d->pos = 0;
    return (DIR *)d;
}

struct dirent *__wrap_readdir(DIR *dirp)
{
    struct g2r_dir *d = (struct g2r_dir *)dirp;
    for (;;) {
        if (d->pos >= d->len) {
            int n = getdents(d->fd, d->buf, (int)sizeof(d->buf));
            if (n <= 0)
                return NULL; /* end (errno untouched) or error (errno set) */
            d->len = n;
            d->pos = 0;
        }
        struct dirent *e = (struct dirent *)(d->buf + d->pos);
        if (e->d_reclen == 0) {
            d->pos = d->len;
            return NULL;
        }
        d->pos += e->d_reclen;
        if (e->d_fileno != 0)
            return e;
    }
}

int __wrap_closedir(DIR *dirp)
{
    struct g2r_dir *d = (struct g2r_dir *)dirp;
    int rc = close(d->fd);
    free(d);
    return rc;
}

/* stdout and stderr go to a log file, never a terminal. */
int isatty(int fd)
{
    (void)fd;
    errno = ENOTTY;
    return 0;
}

/* fnmatch: libcurl (love.system.httpDownload, http.c) calls it for FTP
 * wildcard downloads, and only libScePosixForWebKit exports it. The payload
 * SDK's own fnmatch needs FreeBSD's rune locale tables, which no Sony module
 * exports either. httpDownload never speaks FTP (http.c allows http and
 * https only), but a null import is a crash waiting for the first caller, so
 * this is a real one: POSIX fnmatch for single-byte strings, with
 * FNM_NOESCAPE, FNM_PATHNAME, FNM_PERIOD and FNM_CASEFOLD, and bracket
 * expressions with ranges and negation (no [:class:] names). */
static int g2r_fold(int c, int flags)
{
    c = (unsigned char)c;
    return (flags & FNM_CASEFOLD) ? tolower(c) : c;
}

/* A leading period: at the start of the string, or after a slash when
 * FNM_PATHNAME makes slashes separators. */
static int g2r_leading_period(const char *s, const char *start, int flags)
{
    return (flags & FNM_PERIOD) && *s == '.' &&
           (s == start || ((flags & FNM_PATHNAME) && s[-1] == '/'));
}

/* Matches c against the bracket expression after '['; returns the pattern
 * past the ']' and sets *hit, or NULL when the bracket is not closed (then
 * the '[' is an ordinary character). */
static const char *g2r_bracket(const char *p, int c, int flags, int *hit)
{
    int negate = (*p == '!' || *p == '^');
    if (negate)
        p++;
    int found = 0;
    int first = 1;
    while (*p != ']' || first) {
        first = 0;
        if (*p == 0)
            return NULL;
        int lo = (unsigned char)*p++;
        if (lo == '\\' && !(flags & FNM_NOESCAPE)) {
            if (*p == 0)
                return NULL;
            lo = (unsigned char)*p++;
        }
        int hi = lo;
        if (p[0] == '-' && p[1] != ']' && p[1] != 0) {
            p++;
            hi = (unsigned char)*p++;
            if (hi == '\\' && !(flags & FNM_NOESCAPE)) {
                if (*p == 0)
                    return NULL;
                hi = (unsigned char)*p++;
            }
        }
        int fc = g2r_fold(c, flags);
        if ((c >= lo && c <= hi) || (fc >= g2r_fold(lo, flags) && fc <= g2r_fold(hi, flags)))
            found = 1;
    }
    *hit = found != negate;
    return p + 1;
}

static int g2r_fnmatch(const char *p, const char *s, const char *start, int flags)
{
    for (;;) {
        char pc = *p++;
        switch (pc) {
        case 0:
            return *s == 0 ? 0 : FNM_NOMATCH;
        case '?':
            if (*s == 0 || (*s == '/' && (flags & FNM_PATHNAME)) || g2r_leading_period(s, start, flags))
                return FNM_NOMATCH;
            s++;
            break;
        case '*':
            while (*p == '*')
                p++;
            if (g2r_leading_period(s, start, flags))
                return FNM_NOMATCH;
            if (*p == 0)
                return ((flags & FNM_PATHNAME) && strchr(s, '/') != NULL) ? FNM_NOMATCH : 0;
            for (;; s++) {
                if (g2r_fnmatch(p, s, start, flags) == 0)
                    return 0;
                if (*s == 0 || (*s == '/' && (flags & FNM_PATHNAME)))
                    return FNM_NOMATCH;
            }
        case '[': {
            if (*s == 0 || (*s == '/' && (flags & FNM_PATHNAME)) || g2r_leading_period(s, start, flags))
                return FNM_NOMATCH;
            int hit = 0;
            const char *next = g2r_bracket(p, (unsigned char)*s, flags, &hit);
            if (next == NULL) {
                if (*s != '[')
                    return FNM_NOMATCH;
            } else {
                if (!hit)
                    return FNM_NOMATCH;
                p = next;
            }
            s++;
            break;
        }
        case '\\':
            if (!(flags & FNM_NOESCAPE)) {
                if (*p == 0)
                    return FNM_NOMATCH; /* a dangling escape matches nothing (as glibc) */
                pc = *p++;
            }
            /* fall through */
        default:
            if (g2r_fold(pc, flags) != g2r_fold(*s, flags) || *s == 0)
                return FNM_NOMATCH;
            s++;
            break;
        }
    }
}

int fnmatch(const char *pattern, const char *string, int flags)
{
    return g2r_fnmatch(pattern, string, string, flags);
}

/* zstd (libcurl's zstd content decoding) declares its tracing hooks weak and
 * calls them only when they are defined. The title converter turns an
 * undefined weak symbol into an import nothing exports, so define them: a
 * zero context is zstd's "not tracing". */
unsigned long long ZSTD_trace_decompress_begin(const void *dctx)
{
    (void)dctx;
    return 0;
}

void ZSTD_trace_decompress_end(unsigned long long ctx, const void *trace)
{
    (void)ctx;
    (void)trace;
}
