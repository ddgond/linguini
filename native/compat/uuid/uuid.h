// Stand-in for libuuid covering what libgamestream uses (random v4 UUIDs for
// request IDs). Used on every platform so libuuid isn't a dependency.
#pragma once

#include <stdio.h>
#include <openssl/rand.h>

typedef unsigned char uuid_t[16];

static inline void uuid_generate_random(uuid_t out) {
  RAND_bytes(out, 16);
  out[6] = (out[6] & 0x0F) | 0x40; // version 4
  out[8] = (out[8] & 0x3F) | 0x80; // RFC 4122 variant
}

static inline void uuid_unparse(const uuid_t u, char* out) {
  snprintf(out, 37,
           "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
           u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7],
           u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]);
}
