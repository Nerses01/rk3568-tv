#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

#include <functional>

// Runs a program without a shell and hands back how it ended (step 1.6). Wi-Fi and Bluetooth go through the system's
// own tools (nmcli, bluetoothctl): what they do is what an admin would type, and the tests replace them with stubs.
namespace Command {

struct Result
{
    int exitCode = -1; // -1: it didn't start, or ran out of time
    QString output;
    QString error;
    bool ok() const { return exitCode == 0; }
};

// Calls done on context's thread when program ends, after timeoutMs at the latest; nothing if context goes first
void run(QObject *context, const QString &program, const QStringList &arguments, std::function<void(Result)> done,
         int timeoutMs = 30'000);

// The program for name: the environment variable's value if set (the tests' stubs), otherwise name
QString program(const char *environmentVariable, const QString &name);

} // namespace Command
