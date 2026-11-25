#pragma once
// Shared libcurl TLS CA resolution for pob.http (main thread) and worker pob.http.
// MSYS2 libcurl-4.dll resolves its default CAINFO relative to the DLL, which breaks
// when the DLL is copied into dist/. Resolve explicitly instead.
#include <QByteArray>
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QString>
#include <curl/curl.h>
#include <cstdlib>

namespace pob {

inline void configureTlsCa(CURL* curl) {
    for (const char* envName : {"CURL_CA_BUNDLE", "SSL_CERT_FILE"}) {
        const char* v = std::getenv(envName);
        if (v && *v && QFileInfo(QString::fromLocal8Bit(v)).isFile()) {
            curl_easy_setopt(curl, CURLOPT_CAINFO, v);
            return;
        }
    }
    const QString bundle = QCoreApplication::applicationDirPath() + QStringLiteral("/certs/ca-bundle.crt");
    if (QFileInfo(bundle).isFile()) {
        const QByteArray encoded = QFile::encodeName(bundle);
#if defined(_WIN32)
        // OpenSSL opens CAINFO via ANSI fopen(); if the path cannot round-trip
        // through the local codepage, fall through to NATIVE_CA-only below.
        const bool cainfoUsable = (QString::fromLocal8Bit(encoded) == bundle);
#else
        const bool cainfoUsable = true;
#endif
        if (cainfoUsable) {
            curl_easy_setopt(curl, CURLOPT_CAINFO, encoded.constData()); // libcurl copies the string
#if defined(_WIN32) && defined(CURLSSLOPT_NATIVE_CA)
            curl_easy_setopt(curl, CURLOPT_SSL_OPTIONS, static_cast<long>(CURLSSLOPT_NATIVE_CA));
#endif
            return;
        }
    }
#if defined(_WIN32) && defined(CURLSSLOPT_NATIVE_CA)
    // Clear the broken compiled-in relative default; OpenSSL fails with
    // CURLE_SSL_CACERT_BADFILE otherwise even with NATIVE_CA.
    curl_easy_setopt(curl, CURLOPT_CAINFO, nullptr);
    curl_easy_setopt(curl, CURLOPT_SSL_OPTIONS, static_cast<long>(CURLSSLOPT_NATIVE_CA));
#endif
}

} // namespace pob
