#include <moonbit.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
void moonbit_classify_by_edition_stderr_write(moonbit_bytes_t message) {
  fwrite(message, 1, Moonbit_array_length(message), stderr);
}
