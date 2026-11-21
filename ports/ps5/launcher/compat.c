/* Gen2Recomped PS5: libc functions the title defines itself.
 *
 * A title gets no libScePosixForWebKit and no libkernel_sys, so an import the
 * payload SDK only finds there is a null call at run time.
 * scripts/ps5/check_imports.py lists such imports after linking and fails the
 * build; each one is answered here instead. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
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
