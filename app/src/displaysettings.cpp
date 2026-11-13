#include "displaysettings.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantMap>

#include <algorithm>
#include <fcntl.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

namespace {

QString previousPath()
{
    return DisplaySettings::configPath() + QStringLiteral(".previous");
}

QString attemptsPath()
{
    return DisplaySettings::configPath() + QStringLiteral(".attempts");
}

QByteArray read(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

bool write(const QString &path, const QByteArray &data)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly | QIODevice::Truncate) && file.write(data) == data.size();
}

} // namespace

DisplaySettings::DisplaySettings(QObject *parent) : QObject(parent)
{
    m_current = modeOf(read(configPath()));
    m_modes = modeList(screenModes(), m_current);
    m_awaiting = QFile::exists(previousPath());
}

QString DisplaySettings::configPath()
{
    return qEnvironmentVariable("QT_QPA_EGLFS_KMS_CONFIG");
}

QString DisplaySettings::modeOf(const QByteArray &config)
{
    const QJsonArray outputs = QJsonDocument::fromJson(config).object().value("outputs").toArray();
    return outputs.isEmpty() ? QString() : outputs.first().toObject().value("mode").toString();
}

QByteArray DisplaySettings::withMode(const QByteArray &config, const QString &mode)
{
    QJsonObject root = QJsonDocument::fromJson(config).object();
    if (root.isEmpty())
        root = {{"device", "/dev/dri/card0"}, {"hwcursor", false}};
    QJsonArray outputs = root.value("outputs").toArray();
    QJsonObject output = outputs.isEmpty() ? QJsonObject {{"name", "HDMI1"}} : outputs.first().toObject();
    output["mode"] = mode;
    if (outputs.isEmpty())
        outputs.append(output);
    else
        outputs[0] = output;
    root["outputs"] = outputs;
    return QJsonDocument(root).toJson(QJsonDocument::Compact) + '\n';
}

QVariantList DisplaySettings::modeList(const QList<Mode> &modes, const QString &current)
{
    QList<Mode> list;
    for (const Mode &mode : modes) {
        if (mode.interlaced) // a TV's interlaced modes show the same picture worse
            continue;
        const bool known = std::any_of(list.begin(), list.end(), [&mode](const Mode &m) {
            return m.width == mode.width && m.height == mode.height && m.refresh == mode.refresh;
        });
        if (!known)
            list.append(mode);
        else if (mode.preferred)
            for (Mode &m : list)
                if (m.width == mode.width && m.height == mode.height && m.refresh == mode.refresh)
                    m.preferred = true;
    }
    std::stable_sort(list.begin(), list.end(), [](const Mode &a, const Mode &b) {
        if (a.width * a.height != b.width * b.height)
            return a.width * a.height > b.width * b.height;
        return a.refresh > b.refresh;
    });
    QVariantList result;
    for (const Mode &mode : list) {
        const QString name = QStringLiteral("%1x%2@%3").arg(mode.width).arg(mode.height).arg(mode.refresh);
        QString label = tr("%1 × %2, %3 Hz").arg(mode.width).arg(mode.height).arg(mode.refresh);
        if (mode.preferred)
            label += tr(" (the screen's own)");
        result.append(QVariantMap {{"mode", name}, {"label", label}, {"current", name == current}});
    }
    return result;
}

QList<DisplaySettings::Mode> DisplaySettings::screenModes()
{
    QList<Mode> modes;
    const int fd = open("/dev/dri/card0", O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return modes;
    if (drmModeRes *resources = drmModeGetResources(fd)) {
        for (int i = 0; i < resources->count_connectors && modes.isEmpty(); ++i) {
            drmModeConnector *connector = drmModeGetConnector(fd, resources->connectors[i]);
            if (!connector)
                continue;
            if (connector->connection == DRM_MODE_CONNECTED && connector->connector_type == DRM_MODE_CONNECTOR_HDMIA) {
                for (int m = 0; m < connector->count_modes; ++m) {
                    const drmModeModeInfo &info = connector->modes[m];
                    modes.append({info.hdisplay, info.vdisplay, int(info.vrefresh),
                                  (info.flags & DRM_MODE_FLAG_INTERLACE) != 0,
                                  (info.type & DRM_MODE_TYPE_PREFERRED) != 0});
                }
            }
            drmModeFreeConnector(connector);
        }
        drmModeFreeResources(resources);
    }
    close(fd);
    return modes;
}

bool DisplaySettings::choose(const QString &mode)
{
    const QString path = configPath();
    if (path.isEmpty() || mode == m_current)
        return false;
    const QByteArray old = read(path);
    if (!QFile::exists(previousPath()) && !write(previousPath(), old))
        return false;
    if (!write(path, withMode(old, mode)))
        return false;
    QFile::remove(attemptsPath());
    emit restartRequested();
    return true;
}

void DisplaySettings::keep()
{
    QFile::remove(previousPath());
    QFile::remove(attemptsPath());
    if (m_awaiting) {
        m_awaiting = false;
        emit awaitingConfirmationChanged();
    }
}

void DisplaySettings::revert()
{
    if (!QFile::exists(previousPath()))
        return;
    write(configPath(), read(previousPath()));
    QFile::remove(previousPath());
    QFile::remove(attemptsPath());
    emit restartRequested();
}

void DisplaySettings::recoverBeforeStart()
{
    if (configPath().isEmpty() || !QFile::exists(previousPath()))
        return;
    const int attempts = read(attemptsPath()).trimmed().toInt() + 1;
    if (attempts <= 3) {
        write(attemptsPath(), QByteArray::number(attempts));
        return;
    }
    write(configPath(), read(previousPath()));
    QFile::remove(previousPath());
    QFile::remove(attemptsPath());
}
