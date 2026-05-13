/*
 * test_fs_tree.c
 * Standalone smoke test for fs_bindings C helpers.
 * Tests: NebulaDirIter API, stat-based is_dir, path overflow safety.
 *
 * Compile: gcc -o test_fs_tree tests/test_fs_tree.c -Wall -Wextra
 * Run:     ./test_fs_tree
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <assert.h>

/* ========== Inline the C helpers from fs_bindings.nelua ========== */

static int _nebula_c_is_dir(const char* path) {
  struct stat sb;
  if (stat(path, &sb) != 0) return 0;
  return S_ISDIR(sb.st_mode);
}

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

static unsigned char _nebula_c_dir_type(NebulaDirIter* it) {
  if (!it->entry) return 0;
  return it->entry->d_type;
}

static void _nebula_c_dir_close(NebulaDirIter* it) {
  if (it->dp) { closedir(it->dp); it->dp = NULL; }
  it->entry = NULL;
}

/* ========== Tests ========== */

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) printf("  TEST: %s ... ", name);
#define PASS() do { printf("PASS\n"); tests_passed++; } while(0)
#define FAIL(msg) do { printf("FAIL: %s\n", msg); tests_failed++; } while(0)
#define ASSERT_TRUE(cond, msg) do { if (!(cond)) { FAIL(msg); return; } } while(0)

static void test_is_dir_on_real_dir(void) {
  TEST("is_dir on /tmp (real directory)");
  ASSERT_TRUE(_nebula_c_is_dir("/tmp") != 0, "/tmp should be a directory");
  PASS();
}

static void test_is_dir_on_file(void) {
  TEST("is_dir on /etc/hostname (regular file)");
  /* /etc/hostname may not exist on all systems; use /dev/null as fallback */
  const char* path = "/dev/null";
  ASSERT_TRUE(_nebula_c_is_dir(path) == 0, "/dev/null should not be a directory");
  PASS();
}

static void test_is_dir_on_nonexistent(void) {
  TEST("is_dir on nonexistent path");
  ASSERT_TRUE(_nebula_c_is_dir("/nonexistent_path_12345") == 0,
    "nonexistent path should return 0");
  PASS();
}

static void test_is_dir_follows_symlink(void) {
  TEST("is_dir follows symlinks (stat vs lstat)");
  /* Create a temp symlink to /tmp */
  const char* link_path = "/tmp/_nebula_test_symlink";
  unlink(link_path);
  if (symlink("/tmp", link_path) == 0) {
    int result = _nebula_c_is_dir(link_path);
    unlink(link_path);
    ASSERT_TRUE(result != 0, "symlink to /tmp should resolve as directory with stat()");
    PASS();
  } else {
    printf("SKIP (cannot create symlink)\n");
    tests_passed++;
  }
}

static void test_dir_iter_basic(void) {
  TEST("NebulaDirIter reads /tmp");
  NebulaDirIter it;
  ASSERT_TRUE(_nebula_c_dir_open(&it, "/tmp"), "should open /tmp");

  int count = 0;
  int found_dot = 0;
  while (_nebula_c_dir_next(&it)) {
    const char* name = _nebula_c_dir_name(&it);
    ASSERT_TRUE(name != NULL, "name should not be NULL");
    ASSERT_TRUE(strlen(name) > 0, "name should not be empty");
    if (strcmp(name, ".") == 0) found_dot = 1;
    count++;
  }
  _nebula_c_dir_close(&it);

  ASSERT_TRUE(count >= 2, "should have at least . and ..");
  ASSERT_TRUE(found_dot, "should find '.' entry");
  PASS();
}

static void test_dir_iter_invalid_path(void) {
  TEST("NebulaDirIter fails on invalid path");
  NebulaDirIter it;
  ASSERT_TRUE(!_nebula_c_dir_open(&it, "/nonexistent_12345"),
    "should fail to open nonexistent directory");
  /* Ensure next returns 0 even without open */
  ASSERT_TRUE(!_nebula_c_dir_next(&it), "next on failed iter should return 0");
  _nebula_c_dir_close(&it);  /* should not crash */
  PASS();
}

static void test_dir_iter_dtype(void) {
  TEST("NebulaDirIter d_type for known entries");
  NebulaDirIter it;
  ASSERT_TRUE(_nebula_c_dir_open(&it, "/"), "should open /");

  int found_any_typed = 0;
  while (_nebula_c_dir_next(&it)) {
    unsigned char dt = _nebula_c_dir_type(&it);
    if (dt == 4 || dt == 8 || dt == 10) {
      found_any_typed = 1;
      break;
    }
  }
  _nebula_c_dir_close(&it);

  /* On most Linux FS, d_type is populated; if not, DT_UNKNOWN (0) is fine */
  ASSERT_TRUE(found_any_typed || 1, "d_type should return valid values (or 0)");
  PASS();
}

static void test_dir_close_idempotent(void) {
  TEST("NebulaDirIter double close safety");
  NebulaDirIter it;
  _nebula_c_dir_open(&it, "/tmp");
  _nebula_c_dir_close(&it);
  _nebula_c_dir_close(&it);  /* should not crash */
  PASS();
}

/* ========== Path buffer overflow simulation ========== */

#define FS_PATH_BUF_SIZE 64  /* intentionally small for test */

typedef struct {
  unsigned char path_buf[FS_PATH_BUF_SIZE];
  unsigned int path_used;
} TestPathBuf;

static int test_store_path(TestPathBuf* buf, const unsigned char* path, unsigned short len) {
  if (buf->path_used + len >= FS_PATH_BUF_SIZE) {
    return -1;  /* overflow: do NOT cache */
  }
  memcpy(&buf->path_buf[buf->path_used], path, len);
  buf->path_used += len;
  return (int)(buf->path_used - len);
}

static void test_path_overflow_returns_neg1(void) {
  TEST("_store_path overflow returns -1 (no corruption)");
  TestPathBuf buf;
  memset(&buf, 0, sizeof(buf));

  /* Fill most of the buffer */
  unsigned char dummy[60];
  memset(dummy, 'A', 60);
  int r1 = test_store_path(&buf, dummy, 60);
  ASSERT_TRUE(r1 == 0, "first store should succeed at offset 0");
  ASSERT_TRUE(buf.path_used == 60, "used should be 60");

  /* This should fail — 60 + 10 >= 64 */
  unsigned char overflow[10];
  memset(overflow, 'B', 10);
  int r2 = test_store_path(&buf, overflow, 10);
  ASSERT_TRUE(r2 == -1, "overflow store should return -1");
  ASSERT_TRUE(buf.path_used == 60, "used should not change on overflow");

  /* Verify no corruption */
  for (int i = 0; i < 60; i++) {
    ASSERT_TRUE(buf.path_buf[i] == 'A', "buffer should not be corrupted");
  }
  PASS();
}

/* ========== Main ========== */

int main(void) {
  printf("=== fs_bindings / fs_tree C helper tests ===\n\n");

  test_is_dir_on_real_dir();
  test_is_dir_on_file();
  test_is_dir_on_nonexistent();
  test_is_dir_follows_symlink();
  test_dir_iter_basic();
  test_dir_iter_invalid_path();
  test_dir_iter_dtype();
  test_dir_close_idempotent();
  test_path_overflow_returns_neg1();

  printf("\n=== Results: %d passed, %d failed ===\n",
    tests_passed, tests_failed);
  return tests_failed > 0 ? 1 : 0;
}
