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
//
// It also makes a new handle on every gs_init() and never frees the old one,
// whose kept-alive connection then stalls the host's next TLS handshake with us:
// reconnecting timed out over HTTPS and fell back to HTTP, which always reports
// "not paired". Free the old handle first.
#include <curl/curl.h>

static inline CURL* linguini_curl_easy_init(void) {
  static CURL* previous = NULL;
  if (previous)
    curl_easy_cleanup(previous);
  CURL* curl = curl_easy_init();
  if (curl)
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 5L);
  previous = curl;
  return curl;
}
#define curl_easy_init linguini_curl_easy_init
