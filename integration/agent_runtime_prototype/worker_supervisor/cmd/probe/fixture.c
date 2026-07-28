#include <stdio.h>

#include <moonbit.h>

MOONBIT_FFI_EXPORT
void p2_probe_flush_stdout(void) {
  (void)fflush(stdout);
}
