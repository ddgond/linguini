// Force-included into libgamestream's C sources so they build unmodified
// outside Linux. libgamestream relies on a few POSIX-isms that other
// platforms spell differently.
#pragma once

#include <errno.h>
#include <limits.h>
#include <stdint.h>

#ifdef _WIN32
#include <stdio.h>
#include <winsock2.h>
#include <windows.h>
typedef uint32_t u_int32_t;
#ifndef PATH_MAX
#define PATH_MAX 260
#endif

// Paths come from Godot as UTF-8, but the C runtime's narrow file functions
// read them in the ANSI code page, so a user folder with non-ASCII characters
// in it wouldn't open. Convert to UTF-16 and use the wide functions instead.
static inline int linguini_widen(const char* path, wchar_t* out, int len) {
  return MultiByteToWideChar(CP_UTF8, 0, path, -1, out, len) > 0;
}

static inline FILE* linguini_fopen(const char* path, const char* mode) {
  wchar_t wpath[PATH_MAX], wmode[8];
  if (!linguini_widen(path, wpath, PATH_MAX) || !linguini_widen(mode, wmode, 8))
    return NULL;
  return _wfopen(wpath, wmode);
}
#define fopen linguini_fopen

// mkdirtree() walks the path from the start, so it also tries to make "C:",
// which fails with something other than EEXIST and would stop it early.
// Report anything that already exists as a directory as EEXIST.
static inline int linguini_mkdir(const char* path) {
  wchar_t wpath[PATH_MAX];
  if (!linguini_widen(path, wpath, PATH_MAX)) {
    errno = ENOENT;
    return -1;
  }
  if (CreateDirectoryW(wpath, NULL))
    return 0;
  DWORD attrs = GetFileAttributesW(wpath);
  errno = (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY)) ? EEXIST : ENOENT;
  return -1;
}
#define mkdir(path, mode) linguini_mkdir(path)
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
