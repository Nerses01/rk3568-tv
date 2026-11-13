/* Step 0.6 UI spike: a virtual keyboard through /dev/uinput, so that scripted key presses take the same path as a
 * real keyboard: kernel input device, udev, libinput, Qt. Throwaway measurement code.
 *
 * usage: keys < SCRIPT
 * SCRIPT has one command per line:
 *   up|down|left|right|enter|esc|home|back [HOLD_MS]   press the key, hold it HOLD_MS (default 40), release it
 *   wait MS                                            pause
 * The device appears, waits 2 s for udev and libinput to pick it up, runs the script and disappears.
 * It has no kernel key repeat (no EV_REP): like a real keyboard under libinput, Qt repeats a held key itself.
 */
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static int fd;

static void emit(int type, int code, int value)
{
    struct input_event ev;
    memset(&ev, 0, sizeof ev);
    ev.type = type;
    ev.code = code;
    ev.value = value;
    if (write(fd, &ev, sizeof ev) != sizeof ev) {
        perror("uinput write");
        exit(1);
    }
}

static void sleep_ms(long ms)
{
    struct timespec t = { ms / 1000, (ms % 1000) * 1000000L };
    while (nanosleep(&t, &t) == -1)
        ;
}

static const struct {
    const char *name;
    int code;
} keys[] = {
    { "up", KEY_UP }, { "down", KEY_DOWN }, { "left", KEY_LEFT }, { "right", KEY_RIGHT },
    { "enter", KEY_ENTER }, { "esc", KEY_ESC }, { "home", KEY_HOMEPAGE }, { "back", KEY_BACK },
};

int main(void)
{
    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        perror("/dev/uinput");
        return 1;
    }
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    for (int code = KEY_ESC; code <= KEY_D; ++code)   /* with all of these, udev tags the device a keyboard */
        ioctl(fd, UI_SET_KEYBIT, code);
    for (size_t i = 0; i < sizeof keys / sizeof keys[0]; ++i)
        ioctl(fd, UI_SET_KEYBIT, keys[i].code);
    struct uinput_setup setup;
    memset(&setup, 0, sizeof setup);
    setup.id.bustype = BUS_VIRTUAL;
    setup.id.vendor = 0x1234;
    setup.id.product = 0x0006;
    strcpy(setup.name, "uispike keys");
    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("uinput setup");
        return 1;
    }
    sleep_ms(2000);

    char line[64];
    while (fgets(line, sizeof line, stdin)) {
        char word[16];
        long ms = -1;
        if (sscanf(line, "%15s %ld", word, &ms) < 1 || word[0] == '#')
            continue;
        if (!strcmp(word, "wait")) {
            sleep_ms(ms > 0 ? ms : 0);
            continue;
        }
        int code = -1;
        for (size_t i = 0; i < sizeof keys / sizeof keys[0]; ++i)
            if (!strcmp(word, keys[i].name))
                code = keys[i].code;
        if (code < 0) {
            fprintf(stderr, "keys: unknown key '%s'\n", word);
            continue;
        }
        emit(EV_KEY, code, 1);
        emit(EV_SYN, SYN_REPORT, 0);
        sleep_ms(ms > 0 ? ms : 40);
        emit(EV_KEY, code, 0);
        emit(EV_SYN, SYN_REPORT, 0);
    }
    sleep_ms(200);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
