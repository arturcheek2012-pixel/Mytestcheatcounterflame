#include "Bridge.h"
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

static char g_err[1024] = "";
typedef int (*LauncherMainFn)(int, char **);

const char *css_last_error(void) { return g_err; }

int css_run(const char *dir, int argc, char **argv) {
    char path[2048];
    chdir(dir);
    snprintf(path, sizeof(path), "%s/bin/launcher.dylib", dir);
    void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!h) { snprintf(g_err, sizeof(g_err), "dlopen: %s", dlerror()); return -1; }
    LauncherMainFn fn = (LauncherMainFn)dlsym(h, "LauncherMain");
    if (!fn) { snprintf(g_err, sizeof(g_err), "dlsym: %s", dlerror()); return -1; }
    return fn(argc, argv);
}
