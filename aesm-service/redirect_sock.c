#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>

/*
 * LD_PRELOAD 劫持 connect：把对固定路径 /var/run/aesmd/aesm.socket 的连接改到用户目录下
 * 由 aesmd 容器绑定出来的 socket（与 AESMD_SOCKET_DIR 一致）。
 *
 * 编译：gcc -fPIC -shared -o libredirect.so redirect_sock.c -ldl
 * 使用：AESMD_SOCKET_REDIRECT=$HOME/aesmd-shared/aesm.socket LD_PRELOAD=./libredirect.so ./app
 */

#define DEFAULT_AESM_PATH "/var/run/aesmd/aesm.socket"

int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    static int (*real_connect)(int, const struct sockaddr *, socklen_t) = NULL;
    if (!real_connect)
        real_connect = dlsym(RTLD_NEXT, "connect");

    if (addr->sa_family == AF_UNIX) {
        struct sockaddr_un *un = (struct sockaddr_un *)addr;
        if (strcmp(un->sun_path, DEFAULT_AESM_PATH) == 0) {
            const char *to = getenv("AESMD_SOCKET_REDIRECT");
            if (to && to[0] != '\0') {
                strncpy(un->sun_path, to, sizeof(un->sun_path) - 1);
                un->sun_path[sizeof(un->sun_path) - 1] = '\0';
            }
        }
    }
    return real_connect(sockfd, addr, addrlen);
}
