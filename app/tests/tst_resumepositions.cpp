#include "resumepositions.h"

#include <QStandardPaths>
#include <QTest>

class TestResumePositions : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase() { QStandardPaths::setTestModeEnabled(true); }
    void init() { ResumePositions::forget(file); }

    void unknownFileStartsAtTheBeginning() { QCOMPARE(ResumePositions::position(QStringLiteral("/no/such.mkv")), 0); }

    void remembersAPosition()
    {
        ResumePositions::save(file, 15'000, 600'000);
        QCOMPARE(ResumePositions::position(file), 15'000);
        ResumePositions::save(file, 300'000, 600'000);
        QCOMPARE(ResumePositions::position(file), 300'000);
    }

    void forgetsNearTheStart()
    {
        ResumePositions::save(file, 15'000, 600'000);
        ResumePositions::save(file, 9'999, 600'000);
        QCOMPARE(ResumePositions::position(file), 0);
    }

    void forgetsNearTheEnd()
    {
        ResumePositions::save(file, 15'000, 600'000);
        ResumePositions::save(file, 570'001, 600'000);
        QCOMPARE(ResumePositions::position(file), 0);
        ResumePositions::save(file, 570'000, 600'000);
        QCOMPARE(ResumePositions::position(file), 570'000);
    }

    void unknownDurationKeepsIt()
    {
        ResumePositions::save(file, 20'000, 0);
        QCOMPARE(ResumePositions::position(file), 20'000);
    }

    void forget()
    {
        ResumePositions::save(file, 15'000, 600'000);
        ResumePositions::forget(file);
        QCOMPARE(ResumePositions::position(file), 0);
    }

    void filesAreKeptApart()
    {
        const QString other = QStringLiteral("/userdata/media/b/film.mkv");
        ResumePositions::save(file, 15'000, 600'000);
        ResumePositions::save(other, 25'000, 600'000);
        QCOMPARE(ResumePositions::position(file), 15'000);
        QCOMPARE(ResumePositions::position(other), 25'000);
        ResumePositions::forget(other);
    }

private:
    const QString file = QStringLiteral("/userdata/media/a film/part 1.mkv");
};

QTEST_GUILESS_MAIN(TestResumePositions)
#include "tst_resumepositions.moc"
