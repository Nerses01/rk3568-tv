#include "unixsignals.h"

#include <QSocketNotifier>
#include <QtGlobal>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

namespace {

int pipeFds[2] = {-1, -1};
struct sigaction previous[NSIG];

void handler(int signalNumber)
{
    const int savedErrno = errno;
    const unsigned char byte = static_cast<unsigned char>(signalNumber);
    [[maybe_unused]] const ssize_t written = ::write(pipeFds[1], &byte, 1);
    errno = savedErrno;
}

} // namespace

UnixSignals::UnixSignals(std::initializer_list<int> signalNumbers, QObject *parent) : QObject(parent)
{
    Q_ASSERT_X(pipeFds[0] < 0, "UnixSignals", "only one UnixSignals at a time");
    if (::pipe2(pipeFds, O_CLOEXEC | O_NONBLOCK) != 0) {
        qWarning("UnixSignals: no pipe: %s", strerror(errno));
        return;
    }
    m_notifier = new QSocketNotifier(pipeFds[0], QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &UnixSignals::readPipe);

    struct sigaction action = {};
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    for (int signalNumber : signalNumbers) {
        if (::sigaction(signalNumber, &action, &previous[signalNumber]) == 0)
            m_signals.append(signalNumber);
        else
            qWarning("UnixSignals: cannot handle signal %d: %s", signalNumber, strerror(errno));
    }
}

UnixSignals::~UnixSignals()
{
    for (int signalNumber : std::as_const(m_signals))
        ::sigaction(signalNumber, &previous[signalNumber], nullptr);
    if (pipeFds[0] >= 0) {
        delete m_notifier;
        ::close(pipeFds[0]);
        ::close(pipeFds[1]);
        pipeFds[0] = pipeFds[1] = -1;
    }
}

void UnixSignals::readPipe()
{
    unsigned char byte;
    while (::read(pipeFds[0], &byte, 1) == 1)
        emit received(byte);
}
