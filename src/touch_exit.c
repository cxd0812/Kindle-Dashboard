/* Linux evdev long-press monitor. No EVIOCGRAB: never takes exclusive input.
 * Build: zig cc -target arm-linux-musleabi -mcpu=cortex_a8 -static -Os
 *        -Wall -Wextra -Werror src/touch_exit.c -o extensions/Kindle-Dashboard/bin/touch_exit
 */
#define _POSIX_C_SOURCE 200809L
#include <linux/input.h>
#include <sys/ioctl.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* Kindle uses 32-bit kernel input_event records even with time64 libc. */
_Static_assert(sizeof(struct input_event) == (sizeof(long) == 4 ? 16 : 24),
               "input_event must match the Linux kernel ABI");

#define BIT(a, b) (((a)[(b) / 8] >> ((b) % 8)) & 1)
struct gesture {
    int down, blocked, x, y, have_x, have_y, origin_x, origin_y;
    int tolerance_x, tolerance_y;
    long long since;
};
static long long now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static void frame(struct gesture *g, int contacts, long long now) {
    if (!contacts) {
        g->down = g->blocked = 0;
        return;
    }
    if (contacts != 1) g->blocked = 1;
    if (!g->have_x || !g->have_y) return;
    if (!g->down) {
        g->down = 1;
        g->since = now;
        g->origin_x = g->x;
        g->origin_y = g->y;
    }
    if (abs(g->x - g->origin_x) > g->tolerance_x ||
        abs(g->y - g->origin_y) > g->tolerance_y) g->blocked = 1;
}
static int held(const struct gesture *g, long long now) {
    return g->down && !g->blocked && now - g->since >= 3000 &&
        abs(g->x - g->origin_x) <= g->tolerance_x &&
        abs(g->y - g->origin_y) <= g->tolerance_y;
}
static int self_test(void) {
    struct gesture g = {.have_x=1, .have_y=1, .tolerance_x=30, .tolerance_y=30};
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d\n", __LINE__); return 1; } } while (0)
    frame(&g, 1, 100); CHECK(!held(&g, 3099)); CHECK(held(&g, 3100));
    frame(&g, 0, 3200); CHECK(!held(&g, 10000));
    frame(&g, 1, 4000); g.x = 40; frame(&g, 1, 4100); CHECK(!held(&g, 9000));
    g.x = 0; frame(&g, 1, 5000); CHECK(!held(&g, 10000));
    frame(&g, 0, 10100); frame(&g, 1, 10200); CHECK(held(&g, 13200));
    frame(&g, 2, 13300); CHECK(!held(&g, 20000));
    frame(&g, 1, 20100); CHECK(!held(&g, 25000));
    frame(&g, 0, 25100); frame(&g, 1, 25200); CHECK(held(&g, 28200));
    puts("PASS: long hold, early release, swipe, multi-touch, re-arm");
    return 0;
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    if (argc != 3) { fprintf(stderr, "Usage: touch_exit READY_FILE EXIT_FILE\n"); return 2; }
    int fd = -1, use_mt = 0, has_touch = 0, slots = 0;
    struct gesture g = {0};
    char path[64], name[256] = {0};
    for (int i = 0; i < 32; ++i) {
        unsigned char abs_bits[(ABS_MAX + 8) / 8] = {0};
        unsigned char key_bits[(KEY_MAX + 8) / 8] = {0};
        struct input_absinfo ax, ay;
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;
        ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs_bits)), abs_bits);
        ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key_bits)), key_bits);
        has_touch = BIT(key_bits, BTN_TOUCH);
        use_mt = BIT(abs_bits, ABS_MT_POSITION_X) && BIT(abs_bits, ABS_MT_POSITION_Y);
        slots = use_mt && BIT(abs_bits, ABS_MT_SLOT);
        if ((has_touch || (use_mt && BIT(abs_bits, ABS_MT_TRACKING_ID))) &&
            (use_mt || (BIT(abs_bits, ABS_X) && BIT(abs_bits, ABS_Y))) &&
            ioctl(fd, EVIOCGABS(use_mt ? ABS_MT_POSITION_X : ABS_X), &ax) == 0 &&
            ioctl(fd, EVIOCGABS(use_mt ? ABS_MT_POSITION_Y : ABS_Y), &ay) == 0 &&
            ax.maximum > ax.minimum && ay.maximum > ay.minimum) {
            g.tolerance_x = (ax.maximum - ax.minimum) / 33 + 1;
            g.tolerance_y = (ay.maximum - ay.minimum) / 33 + 1;
            ioctl(fd, EVIOCGNAME(sizeof(name)), name);
            fprintf(stderr, "[Touch] %s (%s), MT=%d slots=%d BTN_TOUCH=%d\n", path, name, use_mt, slots, has_touch);
            break;
        }
        close(fd); fd = -1;
    }
    if (fd < 0) { fprintf(stderr, "[Touch] No supported touchscreen found; refusing takeover.\n"); return 1; }
    FILE *ready = fopen(argv[1], "w");
    if (!ready) { perror("ready file"); close(fd); return 1; }
    fclose(ready);
    int touch = 0, slot = 0, active[32] = {0}, a_contacts = 0, a_seen = 0;
    int dropping = 0, armed = 1, exit_requested = 0;
    /* boot.sh waits for KUAL to release the screen before starting us. */
    struct pollfd pfd = {.fd = fd, .events = POLLIN};
    for (;;) {
        /* No periodic wakeups: evaluate duration when the finger is released. */
        int ret = poll(&pfd, 1, -1);
        if (ret < 0) { if (errno == EINTR) continue; perror("poll"); break; }
        if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) break;
        if (ret > 0) {
            struct input_event e;
            ssize_t n;
            while ((n = read(fd, &e, sizeof(e))) == sizeof(e)) {
                if (e.type == EV_SYN && e.code == SYN_DROPPED) {
                    dropping = 1; armed = 0; g.down = 0; g.blocked = 1;
                    memset(active, 0, sizeof(active)); continue;
                }
                if (dropping) {
                    if (e.type == EV_SYN && e.code == SYN_REPORT) dropping = 0;
                    continue;
                }
                if (e.type == EV_KEY && e.code == BTN_TOUCH) touch = e.value != 0;
                if (e.type == EV_KEY && e.code == BTN_TOOL_DOUBLETAP && e.value) g.blocked = 1;
                if (e.type == EV_ABS) {
                    if (e.code == ABS_MT_SLOT) slot = e.value;
                    if (e.code == ABS_MT_TRACKING_ID) {
                        if (slots && slot >= 0 && slot < 32) active[slot] = e.value >= 0;
                        if (!slots && e.value >= 0) a_seen = 1;
                    }
                    if (!slots || slot == 0) {
                        if (e.code == (use_mt ? ABS_MT_POSITION_X : ABS_X)) { g.x=e.value; g.have_x=1; if (use_mt && !slots) a_seen=1; }
                        if (e.code == (use_mt ? ABS_MT_POSITION_Y : ABS_Y)) { g.y=e.value; g.have_y=1; if (use_mt && !slots) a_seen=1; }
                    }
                }
                if (e.type == EV_SYN && e.code == SYN_MT_REPORT) { a_contacts += a_seen; a_seen=0; }
                if (e.type == EV_SYN && e.code == SYN_REPORT) {
                    int contacts = touch;
                    if (slots) {
                        contacts=0;
                        for (int j=0; j<32; ++j) contacts+=active[j];
                        /* Coordinates belong to slot 0; do not reuse them for another slot. */
                        if (contacts && !active[0]) contacts=2;
                    }
                    else if (use_mt) {
                        int count = a_contacts + a_seen;
                        if (!has_touch) contacts=count;
                        else if (count > 1 && touch) contacts=count;
                    }
                    /* Return only after release so the held touch cannot hit the reader UI. */
                    if (!contacts && armed && held(&g, now_ms())) exit_requested=1;
                    if (!contacts) armed=1;
                    if (armed) frame(&g, contacts, now_ms());
                    a_contacts=a_seen=0;
                }
            }
            if (n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)) break;
        }
        if (exit_requested) {
            FILE *out = fopen(argv[2], "w");
            if (!out) { perror("exit file"); break; }
            fclose(out);
            fprintf(stderr, "[Touch] Long press: exit requested.\n");
            close(fd); return 0;
        }
    }
    close(fd); return 1;
}
