#define _XOPEN_SOURCE 700

#include <moonbit.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char *copy_bytes_as_c_string(moonbit_bytes_t bytes) {
  int32_t length = Moonbit_array_length(bytes);
  if (length < 0 || (size_t)length == SIZE_MAX) {
    return NULL;
  }
  char *copy = libc_malloc((size_t)length + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, bytes, (size_t)length);
  copy[length] = '\0';
  return copy;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_execution_observation_inventory_realpath(
    moonbit_bytes_t path) {
  char *path_copy = copy_bytes_as_c_string(path);
  if (path_copy == NULL) {
    return moonbit_make_bytes(0, 0);
  }

  char *canonical_path = realpath(path_copy, NULL);
  libc_free(path_copy);
  if (canonical_path == NULL) {
    return moonbit_make_bytes(0, 0);
  }

  size_t length = strlen(canonical_path);
  if (length > INT32_MAX) {
    free(canonical_path);
    return moonbit_make_bytes(0, 0);
  }

  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, canonical_path, length);
  free(canonical_path);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_execution_observation_inventory_create_symlink(
    moonbit_bytes_t target, moonbit_bytes_t link) {
  char *target_copy = copy_bytes_as_c_string(target);
  char *link_copy = copy_bytes_as_c_string(link);
  if (target_copy == NULL || link_copy == NULL) {
    libc_free(target_copy);
    libc_free(link_copy);
    return -1;
  }

  int unlink_result = unlink(link_copy);
  if (unlink_result != 0 && errno != ENOENT) {
    libc_free(target_copy);
    libc_free(link_copy);
    return -1;
  }
  int result = symlink(target_copy, link_copy);
  libc_free(target_copy);
  libc_free(link_copy);
  return result == 0 ? 0 : -1;
}
