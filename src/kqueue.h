#pragma once

#include <stdint.h>

typedef int epoll_handle;

typedef union epoll_data {
  void* ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;

struct epoll_event {
  uint32_t events;
  epoll_data_t data;
};

#define EPOLLIN      (1U <<  0)
#define EPOLLPRI     (1U <<  1)
#define EPOLLOUT     (1U <<  2)
#define EPOLLERR     (1U <<  3)
#define EPOLLHUP     (1U <<  4)
#define EPOLLRDNORM  (1U <<  6)
#define EPOLLRDBAND  (1U <<  7)
#define EPOLLWRNORM  (1U <<  8)
#define EPOLLWRBAND  (1U <<  9)
#define EPOLLMSG     (1U << 10)
#define EPOLLRDHUP   (1U << 13)
#define EPOLLONESHOT (1U << 30)
#define EPOLLET      (1U << 31)

#define EPOLL_CTL_ADD 1
#define EPOLL_CTL_MOD 2
#define EPOLL_CTL_DEL 3

#ifdef __cplusplus
extern "C" {
#endif

int epoll_create(int size);
int epoll_create1(int flags);
int epoll_ctl(int epfd, int op, int fd, struct epoll_event* ev);
int epoll_wait(int epfd, struct epoll_event* ev, int max, int timeout);

#ifdef __cplusplus
}
#endif
