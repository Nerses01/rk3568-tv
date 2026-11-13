#pragma once

#include <QString>
#include <QtGlobal>

// Where each video was left, so that it can go on from there (step 1.4). Kept in resume.ini in the app's data folder
// (the user tv's: /var/lib/rk3568-tv/.local/share/rk3568-tv).
class ResumePositions
{
public:
    // Positions closer than this to the start or to the end aren't kept: the film starts from the beginning again
    static constexpr qint64 minimumMs = 10'000;
    static constexpr qint64 endMarginMs = 30'000;

    // Where to start file, in ms; 0 for the beginning
    static qint64 position(const QString &file);

    // Remembers positionMs for file, or forgets file near its start or end (durationMs <= 0: unknown)
    static void save(const QString &file, qint64 positionMs, qint64 durationMs);

    static void forget(const QString &file);
};
