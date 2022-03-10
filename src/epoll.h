#pragma once

#include <string.h>
#include <errno.h>

#if defined(_WIN32)

#include "wepoll.h"
typedef SOCKET epoll_fd;
typedef HANDLE epoll_handle;

#define EPOLL_TYPE "wepoll"

#elif defined(__APPLE__)

#include "epoll_kqueue.h"
#include <unistd.h>
typedef int epoll_fd;
typedef int epoll_handle;

inline int epoll_close(epoll_fd epfd) {
    return close(epfd);
}

#define EPOLL_TYPE "kqueue"

#else

#include <sys/epoll.h>
#include <unistd.h>

typedef int epoll_fd;
typedef int epoll_handle;

inline int epoll_close(epoll_fd epfd) {
    return close(epfd);
}

#define EPOLL_TYPE "epoll"

#endif
