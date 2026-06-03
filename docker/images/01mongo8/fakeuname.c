#define _GNU_SOURCE
#include <string.h>
#include <sys/utsname.h>
#include <dlfcn.h>

int uname(struct utsname *buf) {
    int (*real)(struct utsname *) = dlsym(RTLD_NEXT, "uname");
    int r = real(buf);
    if (r == 0)
        strncpy(buf->release, "6.10.0-safe", sizeof(buf->release) - 1);
    return r;
}
