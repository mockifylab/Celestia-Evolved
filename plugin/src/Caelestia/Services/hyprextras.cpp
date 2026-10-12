#include "hyprextras.hpp"

#include <qdir.h>
#include <qjsonarray.h>
#include <qjsonobject.h>
#include <qlocalsocket.h>
#include <qloggingcategory.h>
#include <qvariant.h>

#include "hyprdevices.hpp"

namespace {

using Qt::StringLiterals::operator""_s;

Q_LOGGING_CATEGORY(lcHypr, "caelestia.services.hypr", QtInfoMsg)

QVariant optionValueFromJson(const QJsonObject& obj) {
    static const QStringList k_types = { u"bool"_s, u"int"_s, u"float"_s, u"str"_s, u"css"_s, u"vec2"_s };
    for (const auto& type : k_types) {
        if (obj.contains(type)) {
            return obj.value(type).toVariant();
        }
    }
    return {};
}

QString luaOptionLiteral(const QVariant& value) {
    if (value.typeId() == QMetaType::QString) {
        auto str = value.toString();
        str.replace(u'"', QStringLiteral("\\\""));
        return u"\"%1\""_s.arg(str);
    }
    return value.toString();
}

} // namespace

namespace caelestia::services::hypr {

using Qt::StringLiterals::operator""_s;

HyprExtras::HyprExtras(QObject* parent)
    : QObject(parent)
    , m_socket(nullptr)
    , m_socketValid(false)
    , m_devices(new HyprDevices(this)) {
    const auto his = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (his.isEmpty()) {
        qCWarning(lcHypr) << "$HYPRLAND_INSTANCE_SIGNATURE is unset. Unable to connect to Hyprland socket.";
        return;
    }

    auto hyprDir = u"%1/hypr/%2"_s.arg(qEnvironmentVariable("XDG_RUNTIME_DIR"), his);
    if (!QDir(hyprDir).exists()) {
        hyprDir = u"/tmp/hypr/"_s + his;

        if (!QDir(hyprDir).exists()) {
            qCWarning(lcHypr) << "Hyprland socket directory does not exist. Unable to connect to Hyprland socket.";
            return;
        }
    }

    m_requestSocket = hyprDir + u"/.socket.sock"_s;
    m_eventSocket = hyprDir + u"/.socket2.sock"_s;

    refreshOptions();
    refreshDevices();

    m_socket = new QLocalSocket(this);

    QObject::connect(m_socket, &QLocalSocket::errorOccurred, this, &HyprExtras::socketError);
    QObject::connect(m_socket, &QLocalSocket::stateChanged, this, &HyprExtras::socketStateChanged);
    QObject::connect(m_socket, &QLocalSocket::readyRead, this, &HyprExtras::readEvent);

    m_socket->connectToServer(m_eventSocket, QLocalSocket::ReadOnly);
}

QVariantHash HyprExtras::options() const {
    return m_options;
}

HyprDevices* HyprExtras::devices() const {
    return m_devices;
}

void HyprExtras::message(const QString& message) {
    if (message.isEmpty()) {
        return;
    }

    makeRequest(message, [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "message: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::batchMessage(const QStringList& messages) {
    if (messages.isEmpty()) {
        return;
    }

    makeRequest(u"[[BATCH]]"_s + messages.join(u";"_s), [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "batchMessage: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::applyOptions(const QVariantHash& options) {
    if (options.isEmpty()) {
        return;
    }

    QString request;
    request.reserve(12 + options.size() * 40);
    request += u"[[BATCH]]"_s;
    for (auto it = options.constBegin(); it != options.constEnd(); ++it) {
        if (!m_usingLua) {
            request += u"keyword "_s + it.key() + u' ' + it.value().toString() + u';';
        } else {
            const auto parts = it.key().split(u':');
            request += u"eval hl.config({ "_s + parts.join(u" = { "_s) + u" = "_s + luaOptionLiteral(it.value()) +
                       u" }"_s.repeated(parts.size() - 1) + u" });"_s;
        }
    }

    makeRequest(request, [this](bool success, const QByteArray& res) {
        if (success) {
            refreshOptions();
        } else {
            qCWarning(lcHypr) << "applyOptions: request error" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::refreshOptions() {
    if (!m_optionsRefresh.isNull()) {
        m_optionsRefresh->close();
    }

    m_optionsRefresh = makeAccumulatedRequest(u"j/descriptions"_s, [this](bool success, const QByteArray& response) {
        m_optionsRefresh.reset();
        if (!success) {
            return;
        }

        const auto options = QJsonDocument::fromJson(response).array();
        bool dirty = false;
        QStringList preciseKeys;

        for (const auto& o : std::as_const(options)) {
            const auto obj = o.toObject();

            // Hyprland <0.55: { value, data: { current } }; >=0.55: { name, current }.
            const bool newFormat = obj.contains(u"name"_s);
            const auto key = newFormat ? obj.value(u"name"_s).toString() : obj.value(u"value"_s).toString();
            if (key.isEmpty()) {
                continue;
            }

            const auto value = newFormat ? obj.value(u"current"_s).toVariant()
                                         : obj.value(u"data"_s).toObject().value(u"current"_s).toVariant();
            if (m_options.value(key) != value) {
                dirty = true;
                m_options.insert(key, value);
            }

            if (newFormat) {
                preciseKeys.append(key);
            }
        }

        if (dirty) {
            emit optionsChanged();
        }

        // The new descriptions schema truncates floats to ints and can report stale
        // booleans, so fetch the authoritative current values in one batched request.
        if (!preciseKeys.isEmpty()) {
            refreshOptionValues(preciseKeys);
        }
    });
}

void HyprExtras::refreshOptionValues(const QStringList& keys) {
    if (!m_valuesRefresh.isNull()) {
        m_valuesRefresh->close();
    }

    QString request;
    request.reserve(12 + keys.size() * 40);
    request += u"[[BATCH]]"_s;
    for (const auto& key : keys) {
        request += u"j/getoption "_s + key + u';';
    }

    m_valuesRefresh = makeAccumulatedRequest(request, [this](bool success, const QByteArray& response) {
        m_valuesRefresh.reset();
        if (!success) {
            return;
        }

        bool dirty = false;

        // Batched responses are separated by three newlines.
        const auto parts = QString::fromUtf8(response).split(u"\n\n\n"_s, Qt::SkipEmptyParts);
        for (const auto& part : parts) {
            const auto trimmed = part.trimmed();
            if (!trimmed.startsWith(u'{')) {
                continue;
            }

            const auto obj = QJsonDocument::fromJson(trimmed.toUtf8()).object();
            const auto key = obj.value(u"option"_s).toString();
            if (key.isEmpty()) {
                continue;
            }

            const auto value = optionValueFromJson(obj);
            if (!value.isValid()) {
                continue;
            }

            if (m_options.value(key) != value) {
                dirty = true;
                m_options.insert(key, value);
            }
        }

        if (dirty) {
            emit optionsChanged();
        }
    });
}

void HyprExtras::refreshDevices() {
    if (!m_devicesRefresh.isNull()) {
        m_devicesRefresh->close();
    }

    m_devicesRefresh = makeRequestJson(u"devices"_s, [this](bool success, const QJsonDocument& response) {
        m_devicesRefresh.reset();
        if (success) {
            m_devices->updateLastIpcObject(response.object());
        }
    });
}

void HyprExtras::socketError(QLocalSocket::LocalSocketError error) const {
    if (!m_socketValid) {
        qCWarning(lcHypr) << "socketError: unable to connect to Hyprland event socket:" << error;
    } else {
        qCWarning(lcHypr) << "socketError: Hyprland event socket error:" << error;
    }
}

void HyprExtras::socketStateChanged(QLocalSocket::LocalSocketState state) {
    if (state == QLocalSocket::UnconnectedState && m_socketValid) {
        qCWarning(lcHypr) << "socketStateChanged: Hyprland event socket disconnected.";
    }

    m_socketValid = state == QLocalSocket::ConnectedState;
}

void HyprExtras::readEvent() {
    while (true) {
        auto rawEvent = m_socket->readLine();
        if (rawEvent.isEmpty()) {
            break;
        }
        rawEvent.truncate(rawEvent.length() - 1); // Remove trailing \n
        const auto sep = rawEvent.indexOf(">>");
        if (sep < 0) {
            qCWarning(lcHypr) << "readEvent: malformed event (no >> separator):" << rawEvent;
            continue;
        }
        handleEvent(QString::fromUtf8(QByteArrayView(rawEvent.data(), sep)));
    }
}

void HyprExtras::handleEvent(const QString& event) {
    if (event == u"configreloaded"_s) {
        refreshOptions();
    } else if (event == u"activelayout"_s) {
        refreshDevices();
    }
}

HyprExtras::SocketPtr HyprExtras::makeRequestJson(
    const QString& request, const std::function<void(bool, QJsonDocument)>& callback) {
    return makeRequest(u"j/"_s + request, [callback](bool success, const QByteArray& response) {
        callback(success, QJsonDocument::fromJson(response));
    });
}

HyprExtras::SocketPtr HyprExtras::makeAccumulatedRequest(
    const QString& request, const std::function<void(bool, QByteArray)>& callback) {
    if (m_requestSocket.isEmpty()) {
        return {};
    }

    auto socket = SocketPtr::create(this);
    const auto buffer = QSharedPointer<QByteArray>::create();
    const auto done = QSharedPointer<bool>::create(false);

    const auto finish = [done, socket, buffer, callback](bool success) {
        if (*done) {
            return;
        }
        *done = true;
        callback(success, std::move(*buffer));
        socket->close();
    };

    QObject::connect(socket.data(), &QLocalSocket::connected, this, [=] {
        socket->write(request.toUtf8());
        socket->flush();
    });

    QObject::connect(socket.data(), &QLocalSocket::readyRead, this, [=] {
        buffer->append(socket->readAll());
    });

    // Large responses (descriptions, option batches) arrive in several chunks; the
    // compositor closes the connection once the full response has been written.
    QObject::connect(socket.data(), &QLocalSocket::disconnected, this, [=] {
        finish(true);
    });

    QObject::connect(socket.data(), &QLocalSocket::errorOccurred, this, [=](QLocalSocket::LocalSocketError err) {
        if (*done) {
            return;
        }

        // Hyprland writes the whole response and then closes the connection. On
        // large replies QLocalSocket can surface that as PeerClosedError instead
        // of a clean disconnected signal, so treat a non-empty buffer as success.
        if (err == QLocalSocket::PeerClosedError) {
            finish(!buffer->isEmpty());
            return;
        }

        qCWarning(lcHypr) << "makeAccumulatedRequest: error making request:" << err << "| request:" << request.left(80);
        finish(false);
    });

    socket->connectToServer(m_requestSocket);

    return socket;
}

HyprExtras::SocketPtr HyprExtras::makeRequest(
    const QString& request, const std::function<void(bool, QByteArray)>& callback) {
    if (m_requestSocket.isEmpty()) {
        return {};
    }

    auto socket = SocketPtr::create(this);

    QObject::connect(socket.data(), &QLocalSocket::connected, this, [=, this] {
        QObject::connect(socket.data(), &QLocalSocket::readyRead, this, [socket, callback] {
            auto response = socket->readAll();
            callback(true, std::move(response));
            socket->close();
        });

        socket->write(request.toUtf8());
        socket->flush();
    });

    QObject::connect(socket.data(), &QLocalSocket::errorOccurred, this, [=](QLocalSocket::LocalSocketError err) {
        qCWarning(lcHypr) << "makeRequest: error making request:" << err << "| request:" << request;
        callback(false, {});
        socket->close();
    });

    socket->connectToServer(m_requestSocket);

    return socket;
}

} // namespace caelestia::services::hypr
