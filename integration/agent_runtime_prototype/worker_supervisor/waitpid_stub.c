#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <moonbit.h>

enum {
  P2_WAIT_ERROR = -1,
  P2_WAIT_RUNNING = 0,
  P2_WAIT_REAPED = 1,
};

enum {
  P2_TERMINAL_EXITED = 1,
  P2_TERMINAL_SIGNALED = 2,
};

MOONBIT_FFI_EXPORT
int32_t p2_waitpid_nohang(
  int32_t pid,
  int32_t *kind_out,
  int32_t *detail_out,
  int32_t *errno_out
) {
  int status = 0;
  pid_t result;

  *kind_out = 0;
  *detail_out = 0;
  *errno_out = 0;
  do {
    result = waitpid((pid_t)pid, &status, WNOHANG);
  } while (result < 0 && errno == EINTR);

  if (result == 0) {
    return P2_WAIT_RUNNING;
  }
  if (result < 0) {
    *errno_out = errno;
    return P2_WAIT_ERROR;
  }
  if (WIFEXITED(status)) {
    *kind_out = P2_TERMINAL_EXITED;
    *detail_out = WEXITSTATUS(status);
    return P2_WAIT_REAPED;
  }
  if (WIFSIGNALED(status)) {
    *kind_out = P2_TERMINAL_SIGNALED;
    *detail_out = WTERMSIG(status);
    return P2_WAIT_REAPED;
  }

  *errno_out = EPROTO;
  return P2_WAIT_ERROR;
}

MOONBIT_FFI_EXPORT
int32_t p2_kill_sigkill(int32_t pid, int32_t *errno_out) {
  *errno_out = 0;
  if (kill((pid_t)pid, SIGKILL) == 0) {
    return 0;
  }
  *errno_out = errno;
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t p2_supervisor_pid(void) {
  return (int32_t)getpid();
}
