/*
 * nebula_fs_helpers.h
 * C helper functions for Nebula Code Browser filesystem operations.
 *
 * Avoids binding struct dirent / struct stat directly from Nelua,
 * since their layout varies across libc implementations (glibc vs musl)
 * and architectures (x86_64 vs aarch64).
 *
 * Uses stat() (not lstat()) so symlinks to directories are followed.
 */
#ifndef NEBULA_FS_HELPERS_H
#define NEBULA_FS_HELPERS_H

#include <dirent.h>
#include <sys/stat.h>

/* Directory check — uses stat() so symlinks to dirs are followed */
static int _nebula_c_is_dir(const char* path) {
  struct stat sb;
  if (stat(path, &sb) != 0) return 0;
  return S_ISDIR(sb.st_mode);
}

/* Opaque iterator for readdir results */
typedef struct { DIR* dp; struct dirent* entry; } NebulaDirIter;

static int _nebula_c_dir_open(NebulaDirIter* it, const char* path) {
  it->dp = opendir(path);
  it->entry = NULL;
  return it->dp != NULL;
}

static int _nebula_c_dir_next(NebulaDirIter* it) {
  if (!it->dp) return 0;
  it->entry = readdir(it->dp);
  return it->entry != NULL;
}

static const char* _nebula_c_dir_name(NebulaDirIter* it) {
  if (!it->entry) return "";
  return it->entry->d_name;
}

/* Returns: 0=unknown, 4=DT_DIR, 8=DT_REG, 10=DT_LNK */
static unsigned char _nebula_c_dir_type(NebulaDirIter* it) {
  if (!it->entry) return 0;
  return it->entry->d_type;
}

static void _nebula_c_dir_close(NebulaDirIter* it) {
  if (it->dp) { closedir(it->dp); it->dp = NULL; }
  it->entry = NULL;
}

#endif /* NEBULA_FS_HELPERS_H */
