#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqml.h> // in Qt 6.2, qqmlregistration.h alone lacks what QML_SINGLETON needs

// The videos on the box (step 1.4): every video file under the media folder, /userdata/media, or RK3568_TV_MEDIA.
// Step 1.5 adds USB drives and folders. QML uses it as the singleton VideoLibrary.
class VideoLibrary : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString folder READ folder CONSTANT)

public:
    using QObject::QObject;

    QString folder() const;

    // The videos, by name in natural order ("2" before "10"): each a map with name (the file's name), path, and
    // place (its folder, relative to the media folder; empty at the top)
    Q_INVOKABLE QVariantList videos() const;

    static bool isVideo(const QString &fileName);
};
