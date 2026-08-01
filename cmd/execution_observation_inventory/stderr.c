#include <moonbit.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
void moonbit_execution_observation_inventory_stderr_write(moonbit_bytes_t message) {
  size_t expected = Moonbit_array_length(message);
  size_t written = fwrite(message, 1, expected, stderr);
  if (written != expected) {
    perror("execution_observation_inventory stderr");
  }
}
