// Force-included into libgamestream's C sources so they build unmodified
// outside Linux. libgamestream relies on a few POSIX-isms that other
// platforms spell differently.
#pragma once

#include <errno.h>
#include <limits.h>
#include <stdint.h>

#ifdef _WIN32
#include <direct.h>
#include <winsock2.h>
#define mkdir(path, mode) _mkdir(path)
typedef uint32_t u_int32_t;
#ifndef PATH_MAX
#define PATH_MAX 260
#endif
#endif

#ifdef __APPLE__
#include <sys/syslimits.h>
#endif

// libgamestream never sets a connect timeout, so an unreachable host would hang
// "Connecting..." for minutes. Wrap its one curl_easy_init() call to add one.
// Only connecting is limited: pairing requests stay open until the PIN is entered.
#include <curl/curl.h>

static inline CURL* linguini_curl_easy_init(void) {
  CURL* curl = curl_easy_init();
  if (curl)
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 5L);
  return curl;
}
#define curl_easy_init linguini_curl_easy_init
