#include "videolibrary.h"

#include <QCollator>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QVariantMap>

#include <algorithm>

QString VideoLibrary::folder() const
{
    const QString configured = qEnvironmentVariable("RK3568_TV_MEDIA");
    return configured.isEmpty() ? QStringLiteral("/userdata/media") : configured;
}

bool VideoLibrary::isVideo(const QString &fileName)
{
    static const QStringList suffixes
        = {QStringLiteral("mkv"), QStringLiteral("mp4"), QStringLiteral("m4v"),  QStringLiteral("webm"),
           QStringLiteral("mov"), QStringLiteral("avi"), QStringLiteral("ts"),   QStringLiteral("m2ts"),
           QStringLiteral("mts"), QStringLiteral("mpg"), QStringLiteral("mpeg"), QStringLiteral("wmv"),
           QStringLiteral("ogv"), QStringLiteral("flv")};
    return suffixes.contains(QFileInfo(fileName).suffix().toLower());
}

QVariantList VideoLibrary::videos() const
{
    const QDir root(folder());
    QList<QFileInfo> files;
    QDirIterator it(root.path(), QDir::Files | QDir::Readable, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        if (isVideo(it.fileName()))
            files.append(it.fileInfo());
    }
    // natural order needs a real locale: in the "C" locale Qt's collator can't compare numbers
    QCollator collator(QLocale::system().language() == QLocale::C ? QLocale(QLocale::English) : QLocale::system());
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(files.begin(), files.end(), [&collator](const QFileInfo &a, const QFileInfo &b) {
        return collator.compare(a.fileName(), b.fileName()) < 0;
    });
    QVariantList result;
    for (const QFileInfo &file : files) {
        const QString place = root.relativeFilePath(file.path());
        result.append(QVariantMap {{QStringLiteral("name"), file.fileName()},
                                   {QStringLiteral("path"), file.absoluteFilePath()},
                                   {QStringLiteral("place"), place == QLatin1String(".") ? QString() : place}});
    }
    return result;
}
