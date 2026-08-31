#include <moonbit.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
void moonbit_candidate_route_probe_stderr_write(moonbit_bytes_t message) {
  size_t expected = Moonbit_array_length(message);
  size_t written = fwrite(message, 1, expected, stderr);
  if (written != expected) {
    perror("candidate_route_probe stderr");
  }
}
