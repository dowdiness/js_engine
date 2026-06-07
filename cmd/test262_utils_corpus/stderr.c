#include <moonbit.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
void moonbit_test262_utils_corpus_stderr_write(moonbit_bytes_t message) {
  fwrite(message, 1, Moonbit_array_length(message), stderr);
}
