// GitHub Copilot 中文版启动器：设置注入环境后交给 launch.sh
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    const char *home = getenv("HOME");
    if (!home) return 1;
    char script[4096];
    snprintf(script, sizeof(script), "%s/Library/Application Support/CopilotCN/launch.sh", home);
    if (access(script, R_OK) != 0) {
        fprintf(stderr, "missing %s, please run install.sh first\n", script);
        return 2;
    }
    char *args[] = {"/bin/bash", script, NULL};
    execv("/bin/bash", args);
    perror("execv");
    return 3;
}
