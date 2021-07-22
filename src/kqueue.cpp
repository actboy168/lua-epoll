#include "kqueue.h"
#include <unistd.h>
#include <errno.h>
#include <sys/event.h>
#include <poll.h>
#include <assert.h>
#include <stdio.h>

#define return_error(error) \
    do {                    \
        errno = (error);    \
        return -1;          \
    } while (0)

#define VAL_BITS 2
#define KEY_BITS (32 - (VAL_BITS))
#define KQUEUE_STATE_REGISTERED 0x0001
#define KQUEUE_STATE_EPOLLRDHUP 0x0002

static int set_state(int kq, uint32_t key, uint16_t val) {
    if ((key & ~(((uint32_t)1 << KEY_BITS) - 1)) || (val & ~(((uint16_t)1 << VAL_BITS) - 1))) {
        return EINVAL;
    }
    struct kevent ev[VAL_BITS * 2];
    int n = 0;
    for (int i = 0; i < VAL_BITS; ++i) {
        uint32_t info_bit = (uint32_t)1 << i;
        uint32_t kev_key = key | (info_bit << KEY_BITS);
        EV_SET(&ev[n], kev_key, EVFILT_USER, EV_ADD, 0, 0, 0);
        ++n;
        if (!(val & info_bit)) {
            EV_SET(&ev[n], kev_key, EVFILT_USER, EV_DELETE, 0, 0, 0);
            ++n;
        }
    }
    int oe = errno;
    if (kevent(kq, ev, n, NULL, 0, NULL) < 0) {
        int e = errno;
        errno = oe;
        return e;
    }
    return 0;
}

static int get_state(int kq, uint32_t key, uint16_t *val) {
    if ((key & ~(((uint32_t)1 << KEY_BITS) - 1))) {
        return_error(EINVAL);
    }
    struct kevent ev[VAL_BITS];
    for (int i = 0; i < VAL_BITS; ++i) {
        uint32_t info_bit = (uint32_t)1 << i;
        uint32_t kev_key = key | (info_bit << KEY_BITS);
        EV_SET(&ev[i], kev_key, EVFILT_USER, EV_RECEIPT, 0, 0, 0);
    }
    int n = kevent(kq, ev, VAL_BITS, ev, VAL_BITS, NULL);
    if (n < 0) {
        return -1;
    }
    uint16_t nval = 0;
    for (int i = 0; i < n; ++i) {
        if (!(ev[i].flags & EV_ERROR)) {
            return_error(EINVAL);
        }
        if (ev[i].data == 0) {
            nval |= (uint32_t)1 << i;
        }
        else if (ev[i].data != ENOENT) {
            return_error(EINVAL);
        }
    }
    *val = nval;
    return 0;
}

static int set_kevent(int epfd, int fd, int read_flags, int write_flags, void* udata) {
    struct kevent ev[2];
    EV_SET(&ev[0], fd, EVFILT_READ, read_flags | EV_RECEIPT, 0, 0, udata);
    EV_SET(&ev[1], fd, EVFILT_WRITE, write_flags | EV_RECEIPT, 0, 0, udata);
    int r = kevent(epfd, ev, 2, ev, 2, NULL);
    if (r < 0) {
        return -1;
    }
    for (int i = 0; i < r; ++i) {
        assert((ev[i].flags & EV_ERROR) != 0);
        if (ev[i].data != 0) {
            errno = ev[i].data;
            return -1;
        }
    }
    return 0;
}

int epoll_create(int size) {
    if (size <= 0) {
        return_error(EINVAL);
    }
    return kqueue();
}

int epoll_create1(int flags) {
    if (flags != 0) {
        return_error(EINVAL);
    }
    return kqueue();
}

int epoll_ctl(int epfd, int op, int fd, struct epoll_event* ev) {
    int flags = 0;
    int read_flags, write_flags;
    if (op != EPOLL_CTL_ADD && op != EPOLL_CTL_MOD && op != EPOLL_CTL_DEL) {
        return_error(EINVAL);
    }
    if ((!ev && op != EPOLL_CTL_DEL) || (ev && ((ev->events & ~(EPOLLIN | EPOLLOUT | EPOLLHUP | EPOLLRDHUP | EPOLLERR))))) {
        return_error(EINVAL);
    }
    if (fd < 0 || ((uint32_t)fd & ~(((uint32_t)1 << KEY_BITS) - 1))) {
        return_error(EBADF);
    }

    if (op == EPOLL_CTL_DEL) {
        int n = set_kevent(epfd, fd, EV_DELETE, EV_DELETE, NULL);
        if (n >= 0) {
            set_state(epfd, fd, 0);
        }
        return n;
    }

    uint16_t kqflags;
    if (get_state(epfd, fd, &kqflags) < 0) {
        return -1;
    }

    if (op == EPOLL_CTL_ADD) {
        if (kqflags & KQUEUE_STATE_REGISTERED) {
            return_error(EEXIST);
        }
        kqflags = KQUEUE_STATE_REGISTERED;
        flags |= EV_ADD;
    }

    if (ev->events & EPOLLET) {
        flags |= EV_CLEAR;
    }
    if (ev->events & EPOLLONESHOT) {
        flags |= EV_ONESHOT;
    }
    if (ev->events & EPOLLRDHUP) {
        kqflags |= KQUEUE_STATE_EPOLLRDHUP;
    }
    read_flags = write_flags = flags | EV_DISABLE;
    if (ev->events & EPOLLIN) {
        read_flags &= ~EV_DISABLE;
        read_flags |= EV_ENABLE;
    }
    if (ev->events & EPOLLOUT) {
        write_flags &= ~EV_DISABLE;
        write_flags |= EV_ENABLE;
    }

    int n = set_kevent(epfd, fd, read_flags, write_flags, ev->data.ptr);
    if (n >= 0) {
        set_state(epfd, fd, kqflags);
    }
    return n;
}

int epoll_wait(int epfd, struct epoll_event* ev, int max, int timeout) {
    struct kevent kev[max];
    struct timespec t, *timeop = &t;
    if (timeout < 0) {
        timeop = NULL;
    }
    else {
        t.tv_sec = timeout / 1000l;
        t.tv_nsec = timeout % 1000l * 1000000l;
    }
    int n = kevent(epfd, NULL, 0, kev, max, timeop);
    if (n == -1) {
        return -1;
    }
    for (int i = 0; i < n; ++i) {
        uint32_t e = 0;
        if (kev[i].filter == EVFILT_READ) {
            e |= EPOLLIN;
        }
        else if (kev[i].filter == EVFILT_WRITE) {
            e |= EPOLLOUT;
        }
        if (kev[i].flags & EV_ERROR) {
            e |= EPOLLERR;
        }
        if (kev[i].flags & EV_EOF) {
            if (kev[i].fflags) {
                e |= EPOLLERR;
            }
            if (kev[i].filter == EVFILT_READ) {
                uint16_t kqflags = 0;
                get_state(epfd, kev[i].ident, &kqflags);
                if (kqflags & KQUEUE_STATE_EPOLLRDHUP) {
                    e |= EPOLLRDHUP;
                }
            }
        }
        ev->events = e;
        ev->data.ptr = kev[i].udata;
        ev++;
    }
    return n;
}
