#include "resumepositions.h"

#include <QCryptographicHash>
#include <QSettings>
#include <QStandardPaths>

namespace {

QString storePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/resume.ini");
}

// A file's path holds slashes, which QSettings reads as groups: the key is a hash of it
QString key(const QString &file)
{
    return QString::fromLatin1(QCryptographicHash::hash(file.toUtf8(), QCryptographicHash::Sha1).toHex());
}

} // namespace

qint64 ResumePositions::position(const QString &file)
{
    return QSettings(storePath(), QSettings::IniFormat).value(key(file), 0).toLongLong();
}

void ResumePositions::save(const QString &file, qint64 positionMs, qint64 durationMs)
{
    if (positionMs < minimumMs || (durationMs > 0 && positionMs > durationMs - endMarginMs)) {
        forget(file);
        return;
    }
    QSettings(storePath(), QSettings::IniFormat).setValue(key(file), positionMs);
}

void ResumePositions::forget(const QString &file)
{
    QSettings(storePath(), QSettings::IniFormat).remove(key(file));
}
