#include <moonbit.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
void moonbit_architecture_state_audit_stderr_write(moonbit_bytes_t message) {
  fwrite(message, 1, Moonbit_array_length(message), stderr);
}
