#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <moonbit.h>

static void p2_write_all(int fd, const char *data, size_t length) {
  size_t offset = 0;
  while (offset < length) {
    ssize_t written = write(fd, data + offset, length - offset);
    if (written > 0) {
      offset += (size_t)written;
    } else if (written < 0 && errno == EINTR) {
      continue;
    } else {
      return;
    }
  }
}

static void p2_hang_forever(void) {
  for (;;) {
    pause();
  }
}

MOONBIT_FFI_EXPORT
void p2_worker_sleep_millis(int32_t milliseconds) {
  struct timespec remaining = {
      .tv_sec = milliseconds / 1000,
      .tv_nsec = (long)(milliseconds % 1000) * 1000000L,
  };
  while (nanosleep(&remaining, &remaining) < 0 && errno == EINTR) {
  }
}

MOONBIT_FFI_EXPORT
void p2_worker_emit_oversized_output_forever(void) {
  char chunk[4096];
  memset(chunk, 'x', sizeof(chunk));
  for (;;) {
    p2_write_all(STDOUT_FILENO, chunk, sizeof(chunk));
  }
}

MOONBIT_FFI_EXPORT
void p2_worker_emit_malformed_then_hang(void) {
  static const char message[] = "{malformed-json}\n";
  p2_write_all(STDOUT_FILENO, message, sizeof(message) - 1);
  p2_hang_forever();
}

MOONBIT_FFI_EXPORT
void p2_worker_emit_partial_close_then_hang(void) {
  static const char message[] = "{\"kind\":\"partial\"";
  p2_write_all(STDOUT_FILENO, message, sizeof(message) - 1);
  close(STDOUT_FILENO);
  p2_hang_forever();
}

MOONBIT_FFI_EXPORT
void p2_worker_abrupt_exit_process(void) {
  _exit(86);
}
