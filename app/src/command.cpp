#include "command.h"

#include <QProcess>
#include <QTimer>
#include <QVariant>

namespace Command {

void run(QObject *context, const QString &program, const QStringList &arguments, std::function<void(Result)> done,
         int timeoutMs)
{
    auto *process = new QProcess(context);
    auto *timer = new QTimer(process);
    timer->setSingleShot(true);
    auto finish = [process, done](Result result) {
        if (process->property("finished").toBool())
            return;
        process->setProperty("finished", true);
        process->deleteLater();
        done(result);
    };
    QObject::connect(process, &QProcess::finished, process, [process, finish](int code, QProcess::ExitStatus status) {
        finish({status == QProcess::NormalExit ? code : -1, QString::fromUtf8(process->readAllStandardOutput()),
                QString::fromUtf8(process->readAllStandardError())});
    });
    QObject::connect(process, &QProcess::errorOccurred, process, [process, finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            finish({-1, {}, process->errorString()});
    });
    QObject::connect(timer, &QTimer::timeout, process, [process, finish] {
        process->kill();
        finish({-1, QString::fromUtf8(process->readAllStandardOutput()), QStringLiteral("timed out")});
    });
    timer->start(timeoutMs);
    process->start(program, arguments);
}

QString program(const char *environmentVariable, const QString &name)
{
    const QString configured = qEnvironmentVariable(environmentVariable);
    return configured.isEmpty() ? name : configured;
}

} // namespace Command
