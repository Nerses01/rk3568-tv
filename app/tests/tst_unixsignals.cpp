#include "unixsignals.h"

#include <QSignalSpy>
#include <QTest>

#include <csignal>

class TestUnixSignals : public QObject
{
    Q_OBJECT

private slots:
    void signalArrivesThroughTheEventLoop();
    void terminateDoesNotKill();
    void signalsNotAskedForAreLeftAlone();
    void earlierHandlerComesBack();
    void severalSignalsInARow();

private:
    static void countingHandler(int) { ++s_counted; }
    static inline int s_counted = 0;
};

void TestUnixSignals::signalArrivesThroughTheEventLoop()
{
    UnixSignals unixSignals({SIGUSR1});
    QSignalSpy spy(&unixSignals, &UnixSignals::received);
    ::raise(SIGUSR1);
    QVERIFY(spy.wait(1000));
    QCOMPARE(spy.count(), 1);
    QCOMPARE(spy.at(0).at(0).toInt(), SIGUSR1);
}

void TestUnixSignals::terminateDoesNotKill()
{
    // what systemd sends to stop the app: the process lives on, and the event loop hears of it
    UnixSignals unixSignals({SIGTERM, SIGINT});
    QSignalSpy spy(&unixSignals, &UnixSignals::received);
    ::raise(SIGTERM);
    QVERIFY(spy.wait(1000));
    QCOMPARE(spy.at(0).at(0).toInt(), SIGTERM);
}

void TestUnixSignals::signalsNotAskedForAreLeftAlone()
{
    s_counted = 0;
    struct sigaction counting = {};
    counting.sa_handler = countingHandler;
    struct sigaction old;
    ::sigaction(SIGUSR2, &counting, &old);
    {
        UnixSignals unixSignals({SIGUSR1});
        QSignalSpy spy(&unixSignals, &UnixSignals::received);
        ::raise(SIGUSR2);
        QCOMPARE(s_counted, 1);
        QVERIFY(!spy.wait(100));
    }
    ::sigaction(SIGUSR2, &old, nullptr);
}

void TestUnixSignals::earlierHandlerComesBack()
{
    s_counted = 0;
    struct sigaction counting = {};
    counting.sa_handler = countingHandler;
    struct sigaction old;
    ::sigaction(SIGUSR1, &counting, &old);
    {
        UnixSignals unixSignals({SIGUSR1});
        ::raise(SIGUSR1);
        QCOMPARE(s_counted, 0); // taken over
    }
    ::raise(SIGUSR1);
    QCOMPARE(s_counted, 1); // given back
    ::sigaction(SIGUSR1, &old, nullptr);
}

void TestUnixSignals::severalSignalsInARow()
{
    UnixSignals unixSignals({SIGUSR1, SIGUSR2});
    QSignalSpy spy(&unixSignals, &UnixSignals::received);
    ::raise(SIGUSR1);
    ::raise(SIGUSR2);
    ::raise(SIGUSR1);
    QTRY_COMPARE_WITH_TIMEOUT(spy.count(), 3, 1000);
    QCOMPARE(spy.at(1).at(0).toInt(), SIGUSR2);
}

QTEST_GUILESS_MAIN(TestUnixSignals)
#include "tst_unixsignals.moc"
