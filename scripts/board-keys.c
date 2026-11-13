/* The developer's remote control (step 0.7), run on the board by `scripts/board.sh keys`. It presses keys through
 * a virtual keyboard on /dev/uinput, so that they reach the app the way a real keyboard's do: kernel, udev,
 * libinput, Qt.
 *
 * usage: board-keys KEY...
 *   KEY        up, down, left, right, enter, back, home, menu, esc, space, playpause, volumeup, volumedown
 *   KEY:MS     the same key held for MS milliseconds (default 40); Qt repeats a key held long enough
 *   wait:MS    a pause
 * The keyboard appears, waits 2 s for libinput to pick it up, presses the keys and disappears. It has no kernel
 * key repeat (no EV_REP): like a real keyboard under libinput, Qt repeats a held key itself.
 * With BOARD_KEYS_DRY_RUN=1 it prints what it would do and needs no /dev/uinput (for the tests).
 * Exit status: 0; 1 if /dev/uinput fails; 2 for a bad argument, before any key is pressed.
 */
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static const struct
{
    const char *name;
    int code;
} keys[] = {
    {"up", KEY_UP},
    {"down", KEY_DOWN},
    {"left", KEY_LEFT},
    {"right", KEY_RIGHT},
    {"enter", KEY_ENTER},
    {"back", KEY_BACK},
    {"home", KEY_HOMEPAGE},
    {"menu", KEY_MENU},
    {"esc", KEY_ESC},
    {"space", KEY_SPACE},
    {"playpause", KEY_PLAYPAUSE},
    {"volumeup", KEY_VOLUMEUP},
    {"volumedown", KEY_VOLUMEDOWN},
};
enum { NKEYS = sizeof keys / sizeof keys[0] };

struct step
{
    int key; /* index into keys, or -1 for a pause */
    long ms; /* hold time, or pause */
};

static int fd = -1;

static void sleep_ms(long ms)
{
    struct timespec t = {ms / 1000, (ms % 1000) * 1000000L};
    while (nanosleep(&t, &t) == -1)
        ;
}

static void emit(int type, int code, int value)
{
    struct input_event ev;
    memset(&ev, 0, sizeof ev);
    ev.type = type;
    ev.code = code;
    ev.value = value;
    if (write(fd, &ev, sizeof ev) != sizeof ev) {
        perror("board-keys: /dev/uinput");
        exit(1);
    }
}

/* "MS" -> 1..60000, or -1 */
static long parse_ms(const char *s)
{
    char *end;
    long ms = strtol(s, &end, 10);
    return (*s && !*end && ms >= 1 && ms <= 60000) ? ms : -1;
}

static int parse(const char *arg, struct step *step)
{
    char name[16];
    const char *colon = strchr(arg, ':');
    size_t len = colon ? (size_t)(colon - arg) : strlen(arg);
    if (len == 0 || len >= sizeof name)
        return -1;
    memcpy(name, arg, len);
    name[len] = '\0';
    step->ms = colon ? parse_ms(colon + 1) : 40;
    if (step->ms < 0)
        return -1;
    if (!strcmp(name, "wait")) {
        step->key = -1;
        return colon ? 0 : -1;
    }
    for (int i = 0; i < NKEYS; ++i)
        if (!strcmp(name, keys[i].name)) {
            step->key = i;
            return 0;
        }
    return -1;
}

static int open_keyboard(void)
{
    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        perror("board-keys: /dev/uinput");
        return -1;
    }
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    for (int code = KEY_ESC; code <= KEY_D; ++code) /* with all of these, udev tags the device a keyboard */
        ioctl(fd, UI_SET_KEYBIT, code);
    for (int i = 0; i < NKEYS; ++i)
        ioctl(fd, UI_SET_KEYBIT, keys[i].code);
    struct uinput_setup setup;
    memset(&setup, 0, sizeof setup);
    setup.id.bustype = BUS_VIRTUAL;
    setup.id.vendor = 0x1234;
    setup.id.product = 0x0007;
    strcpy(setup.name, "rk3568-tv board-keys");
    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("board-keys: uinput setup");
        return -1;
    }
    sleep_ms(2000);
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: board-keys KEY[:MS]... | wait:MS\n");
        return 2;
    }
    struct step *steps = calloc(argc - 1, sizeof *steps);
    if (!steps)
        return 1;
    for (int i = 1; i < argc; ++i)
        if (parse(argv[i], &steps[i - 1]) < 0) {
            fprintf(stderr, "board-keys: not a key: '%s'\n", argv[i]);
            return 2;
        }

    const char *dry = getenv("BOARD_KEYS_DRY_RUN");
    const int dry_run = dry && *dry && strcmp(dry, "0");
    if (!dry_run && open_keyboard() < 0)
        return 1;
    for (int i = 0; i < argc - 1; ++i) {
        const struct step *s = &steps[i];
        if (dry_run) {
            if (s->key < 0)
                printf("wait %ld\n", s->ms);
            else
                printf("key %s %ld\n", keys[s->key].name, s->ms);
            continue;
        }
        if (s->key < 0) {
            sleep_ms(s->ms);
            continue;
        }
        emit(EV_KEY, keys[s->key].code, 1);
        emit(EV_SYN, SYN_REPORT, 0);
        sleep_ms(s->ms);
        emit(EV_KEY, keys[s->key].code, 0);
        emit(EV_SYN, SYN_REPORT, 0);
        sleep_ms(60); /* a gap between presses, as a person's fingers leave */
    }
    if (!dry_run) {
        sleep_ms(200);
        ioctl(fd, UI_DEV_DESTROY);
        close(fd);
    }
    free(steps);
    return 0;
}
