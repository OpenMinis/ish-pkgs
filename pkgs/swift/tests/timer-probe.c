/* Probes the kernel behaviours libdispatch's timer path (src/event/event_epoll.c)
 * relies on. Each check prints PASS/FAIL; on Linux all pass.
 *   cc -O2 -static timer-probe.c -o timer-probe && ./timer-probe [rounds]
 */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>

static int fails;
static void check(const char *what, int ok, const char *detail) {
    printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", what, detail[0] ? "  -- " : "", detail);
    if (!ok) fails++;
}
static struct timespec now_plus_ns(clockid_t c, long long ns) {
    struct timespec t; clock_gettime(c, &t);
    long long v = (long long)t.tv_sec * 1000000000LL + t.tv_nsec + ns;
    if (v < 1) v = 1;
    t.tv_sec = v / 1000000000LL; t.tv_nsec = v % 1000000000LL; return t;
}
static int readable(int fd, int ms) { struct pollfd p = { fd, POLLIN, 0 }; return poll(&p, 1, ms) == 1; }
static int ep_wait(int ep, int ms) { struct epoll_event e; int r; do r = epoll_wait(ep, &e, 1, ms); while (r < 0 && errno == EINTR); return r; }

static void one_clock(const char *name, clockid_t clk, int rounds) {
    char buf[160], d[160];
    int fd = timerfd_create(clk, TFD_NONBLOCK | TFD_CLOEXEC);
    snprintf(buf, sizeof buf, "[%s] timerfd_create", name);
    snprintf(d, sizeof d, "%s", fd < 0 ? strerror(errno) : "");
    check(buf, fd >= 0, d);
    if (fd < 0) return;
    struct itimerspec its = {0};

    /* 1. absolute target already in the past must fire immediately (libdispatch arms
     *    with TFD_TIMER_ABSTIME and the target is often already due under load) */
    int bad = 0;
    for (int i = 0; i < rounds; i++) {
        its.it_value = now_plus_ns(clk, -(long long)(i % 5) * 1000000LL - 1);
        if (timerfd_settime(fd, TFD_TIMER_ABSTIME, &its, NULL) != 0 || !readable(fd, 200)) bad++;
    }
    snprintf(buf, sizeof buf, "[%s] ABSTIME target in the past fires at once", name);
    snprintf(d, sizeof d, "%d/%d rounds did not become readable within 200 ms", bad, rounds);
    check(buf, bad == 0, bad ? d : "");

    /* 2. re-arming must clear a pending expiration WITHOUT read() (libdispatch never reads the timerfd) */
    its.it_value = now_plus_ns(clk, 3000000000LL);
    timerfd_settime(fd, TFD_TIMER_ABSTIME, &its, NULL);
    snprintf(buf, sizeof buf, "[%s] settime clears a pending expiration without read()", name);
    check(buf, !readable(fd, 50), "");

    /* 3. EPOLLONESHOT: after an event, settime + EPOLL_CTL_MOD must deliver the next expiration,
     *    including when the fd is ALREADY readable at the time of the MOD */
    int ep = epoll_create1(EPOLL_CLOEXEC);
    struct epoll_event ev = { .events = EPOLLONESHOT | EPOLLIN, .data.u32 = 7 };
    its.it_value = now_plus_ns(clk, 1000000);
    timerfd_settime(fd, TFD_TIMER_ABSTIME, &its, NULL);
    int add = epoll_ctl(ep, EPOLL_CTL_ADD, fd, &ev);
    int lost_future = 0, lost_ready = 0, spurious = 0;
    if (add == 0 && ep_wait(ep, 500) != 1) lost_future++;
    for (int i = 0; i < rounds; i++) {
        /* a: next target 1 ms in the future, then MOD */
        its.it_value = now_plus_ns(clk, 1000000);
        timerfd_settime(fd, TFD_TIMER_ABSTIME, &its, NULL);
        epoll_ctl(ep, EPOLL_CTL_MOD, fd, &ev);
        if (ep_wait(ep, 500) != 1) lost_future++;
        /* oneshot must stay quiet until re-armed, although the fd is still readable */
        if (ep_wait(ep, 2) != 0) spurious++;
        /* b: target in the past (already readable), then MOD */
        its.it_value = now_plus_ns(clk, -1000);
        timerfd_settime(fd, TFD_TIMER_ABSTIME, &its, NULL);
        usleep(200);
        epoll_ctl(ep, EPOLL_CTL_MOD, fd, &ev);
        if (ep_wait(ep, 500) != 1) lost_ready++;
    }
    snprintf(buf, sizeof buf, "[%s] ONESHOT re-arm (MOD) delivers a future expiration", name);
    snprintf(d, sizeof d, "%d/%d lost", lost_future, rounds + 1);
    check(buf, add == 0 && lost_future == 0, lost_future ? d : (add ? "EPOLL_CTL_ADD failed" : ""));
    snprintf(buf, sizeof buf, "[%s] ONESHOT re-arm (MOD) on an already-readable fd delivers", name);
    snprintf(d, sizeof d, "%d/%d lost", lost_ready, rounds);
    check(buf, lost_ready == 0, lost_ready ? d : "");
    snprintf(buf, sizeof buf, "[%s] ONESHOT stays disarmed until MOD", name);
    snprintf(d, sizeof d, "%d/%d spurious events", spurious, rounds);
    check(buf, spurious == 0, spurious ? d : "");
    close(ep); close(fd);
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 2000;
    setvbuf(stdout, NULL, _IONBF, 0);
    one_clock("CLOCK_MONOTONIC", CLOCK_MONOTONIC, rounds);   /* dispatch "uptime" clock */
    one_clock("CLOCK_BOOTTIME", CLOCK_BOOTTIME, rounds);     /* dispatch "monotonic" clock: Task.sleep(for:) */
    one_clock("CLOCK_REALTIME", CLOCK_REALTIME, rounds);     /* dispatch wall clock */

    /* 4. the manager thread is woken through an eventfd registered level-triggered in epoll */
    int ep = epoll_create1(EPOLL_CLOEXEC), efd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK), lost = 0;
    struct epoll_event ev = { .events = EPOLLIN, .data.u32 = 1 };
    epoll_ctl(ep, EPOLL_CTL_ADD, efd, &ev);
    for (int i = 0; i < rounds; i++) {
        eventfd_t v;
        eventfd_write(efd, 1);
        if (ep_wait(ep, 200) != 1) lost++;
        eventfd_read(efd, &v);
        if (ep_wait(ep, 0) != 0) lost++;
    }
    char d[64]; snprintf(d, sizeof d, "%d/%d wrong", lost, rounds);
    check("eventfd wake-up through epoll", lost == 0, lost ? d : "");
    printf(fails ? "\n%d check(s) FAILED\n" : "\nall checks passed\n", fails);
    return fails != 0;
}
