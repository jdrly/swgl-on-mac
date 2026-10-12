// Contents/MacOS/SWGLonMac: the app's main executable. Runs Contents/Resources/main.sh with
// the app's arguments (same process, so the app keeps its identity for the Java launcher
// main.sh finally execs). Native rather than the script itself so the app can be signed
// with the hardened runtime and notarized.
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    char exe[PATH_MAX], real[PATH_MAX], script[PATH_MAX];
    uint32_t size = sizeof(exe);
    if (_NSGetExecutablePath(exe, &size) != 0 || !realpath(exe, real)) {
        fprintf(stderr, "SWGLonMac: cannot locate the app\n");
        return 1;
    }
    char *slash = strrchr(real, '/');  // …/Contents/MacOS/SWGLonMac
    if (!slash) return 1;
    *slash = 0;
    snprintf(script, sizeof(script), "%s/../Resources/main.sh", real);

    char **args = calloc((size_t)argc + 2, sizeof(*args));
    if (!args) return 1;
    args[0] = "/bin/bash";
    args[1] = script;
    for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
    execv("/bin/bash", args);
    perror("SWGLonMac: /bin/bash");
    return 1;
}
