#pragma once

#include <QObject>

#include <initializer_list>

class QSocketNotifier;

// Turns Unix signals into a Qt signal, so that the app can quit through its event loop when systemd stops it.
// On EGLFS, Qt's own SIGTERM handler restores the console and calls _exit(1): systemd then counts a normal stop as a
// failure, and nothing of the app's shutdown runs (docs/05-development.md). Created after QGuiApplication, the
// handlers here replace Qt's; Qt still restores the console when the app exits normally.
//
// The handler only writes the signal's number to a pipe (async-signal-safe); the pipe's reading end is watched by
// the event loop. One UnixSignals at a time; its destructor puts the earlier handlers back.
class UnixSignals : public QObject
{
    Q_OBJECT

public:
    explicit UnixSignals(std::initializer_list<int> signalNumbers, QObject *parent = nullptr);
    ~UnixSignals() override;

signals:
    void received(int signalNumber);

private:
    void readPipe();

    QSocketNotifier *m_notifier = nullptr;
    QList<int> m_signals;
};
