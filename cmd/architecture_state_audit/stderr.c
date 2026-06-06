#include <moonbit.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
void moonbit_architecture_state_audit_stderr_write(moonbit_bytes_t message) {
  fputs((const char *)message, stderr);
}
