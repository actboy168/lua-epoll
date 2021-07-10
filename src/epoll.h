#pragma once

#include <string.h>
#include <errno.h>

#if defined(_WIN32)

#include "wepoll.h"
typedef SOCKET epoll_fd;
typedef HANDLE epoll_handle;

#else

#include <sys/epoll.h>
#include <unistd.h>

typedef int epoll_fd;
typedef int epoll_handle;

inline int epoll_close(epoll_fd epfd) {
    return close(epfd);
}

#endif
