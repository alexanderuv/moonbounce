// Counts allocations by putting a counting wrapper in front of each C
// allocator entry point. Each wrapper adds one to the count and calls the real
// allocator, so memory comes from the same place and frees the same way.
// `realloc` counts as an allocation, as in the Jolt harness.

#include "CounterShims.h"

// Any C library header defines __GLIBC__ under glibc.
#include <stdlib.h>

#if defined(__APPLE__) || defined(__GLIBC__)

#include <stdatomic.h>

static _Atomic uint64_t allocations = 0;

static inline void count_allocation(void) {
    atomic_fetch_add_explicit(&allocations, 1, memory_order_relaxed);
}

bool allocations_are_counted(void) { return true; }

uint64_t allocation_count(void) {
    return atomic_load_explicit(&allocations, memory_order_relaxed);
}

#else

bool allocations_are_counted(void) { return false; }

uint64_t allocation_count(void) { return 0; }

#endif

#if defined(__APPLE__)

// dyld's interposing: each pair in the __interpose section redirects every
// other loaded image's calls to the original, the Swift runtime and libSystem
// included. Calls from this image are left alone, so the wrappers below reach
// the real allocator. dyld ignores the section in a main executable, which is
// why this is a dynamic library on macOS (Package.swift).
//
// The typed `malloc_type_*` entry points are where the Swift runtime
// allocates; the rest cover C callers and zones.

#include <malloc/malloc.h>
#include <pthread.h>
#include <stdlib.h>

#define INTERPOSE(replacement, original)                                      \
    __attribute__((used)) static const struct {                               \
        const void *replacement_function;                                     \
        const void *original_function;                                        \
    } interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)&replacement, (const void *)&original                   \
    };

// libmalloc's entry points call one another, `malloc_type_malloc` calling
// `malloc` for one, and dyld redirects those calls too. So each thread counts
// only its outermost call. The depth lives in a pthread key: a C thread-local
// in a dynamic library is allocated on first use, which would recurse into
// these wrappers.
static pthread_key_t depth_key;
static bool depth_key_ready = false;

__attribute__((constructor)) static void create_depth_key(void) {
    depth_key_ready = pthread_key_create(&depth_key, NULL) == 0;
}

static inline void enter(void) {
    // Allocations before the constructor runs, while dyld loads libraries,
    // are counted without the check.
    if (!depth_key_ready) {
        count_allocation();
        return;
    }
    uintptr_t depth = (uintptr_t)pthread_getspecific(depth_key);
    if (depth == 0) {
        count_allocation();
    }
    pthread_setspecific(depth_key, (void *)(depth + 1));
}

static inline void leave(void) {
    if (!depth_key_ready) {
        return;
    }
    uintptr_t depth = (uintptr_t)pthread_getspecific(depth_key);
    pthread_setspecific(depth_key, (void *)(depth - 1));
}

// The body of a wrapper that returns `call`'s result of type `type`.
#define COUNTED(type, call)       \
    {                             \
        enter();                  \
        type result = call;       \
        leave();                  \
        return result;            \
    }

static void *counting_malloc(size_t size)
    COUNTED(void *, malloc(size))
static void *counting_calloc(size_t count, size_t size)
    COUNTED(void *, calloc(count, size))
static void *counting_realloc(void *block, size_t size)
    COUNTED(void *, realloc(block, size))
static void *counting_reallocf(void *block, size_t size)
    COUNTED(void *, reallocf(block, size))
static void *counting_valloc(size_t size)
    COUNTED(void *, valloc(size))
static void *counting_aligned_alloc(size_t alignment, size_t size)
    COUNTED(void *, aligned_alloc(alignment, size))
static int counting_posix_memalign(void **block, size_t alignment, size_t size)
    COUNTED(int, posix_memalign(block, alignment, size))

static void *counting_malloc_zone_malloc(malloc_zone_t *zone, size_t size)
    COUNTED(void *, malloc_zone_malloc(zone, size))
static void *counting_malloc_zone_calloc(malloc_zone_t *zone, size_t count, size_t size)
    COUNTED(void *, malloc_zone_calloc(zone, count, size))
static void *counting_malloc_zone_realloc(malloc_zone_t *zone, void *block, size_t size)
    COUNTED(void *, malloc_zone_realloc(zone, block, size))
static void *counting_malloc_zone_valloc(malloc_zone_t *zone, size_t size)
    COUNTED(void *, malloc_zone_valloc(zone, size))
static void *counting_malloc_zone_memalign(malloc_zone_t *zone, size_t alignment, size_t size)
    COUNTED(void *, malloc_zone_memalign(zone, alignment, size))
static void *counting_malloc_zone_malloc_with_options(malloc_zone_t *zone, size_t alignment, size_t size,
                                                      malloc_zone_malloc_options_t options)
    COUNTED(void *, malloc_zone_malloc_with_options(zone, alignment, size, options))

static void *counting_malloc_type_malloc(size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_malloc(size, type))
static void *counting_malloc_type_calloc(size_t count, size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_calloc(count, size, type))
static void *counting_malloc_type_realloc(void *block, size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_realloc(block, size, type))
static void *counting_malloc_type_valloc(size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_valloc(size, type))
static void *counting_malloc_type_aligned_alloc(size_t alignment, size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_aligned_alloc(alignment, size, type))
static int counting_malloc_type_posix_memalign(void **block, size_t alignment, size_t size, malloc_type_id_t type)
    COUNTED(int, malloc_type_posix_memalign(block, alignment, size, type))
static void *counting_malloc_type_zone_malloc(malloc_zone_t *zone, size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_zone_malloc(zone, size, type))
static void *counting_malloc_type_zone_calloc(malloc_zone_t *zone, size_t count, size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_zone_calloc(zone, count, size, type))
static void *counting_malloc_type_zone_realloc(malloc_zone_t *zone, void *block, size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_zone_realloc(zone, block, size, type))
static void *counting_malloc_type_zone_valloc(malloc_zone_t *zone, size_t size, malloc_type_id_t type)
    COUNTED(void *, malloc_type_zone_valloc(zone, size, type))
static void *counting_malloc_type_zone_memalign(malloc_zone_t *zone, size_t alignment, size_t size,
                                                malloc_type_id_t type)
    COUNTED(void *, malloc_type_zone_memalign(zone, alignment, size, type))
static void *counting_malloc_type_zone_malloc_with_options(malloc_zone_t *zone, size_t alignment, size_t size,
                                                           malloc_type_id_t type, malloc_zone_malloc_options_t options)
    COUNTED(void *, malloc_type_zone_malloc_with_options(zone, alignment, size, type, options))

INTERPOSE(counting_malloc, malloc)
INTERPOSE(counting_calloc, calloc)
INTERPOSE(counting_realloc, realloc)
INTERPOSE(counting_reallocf, reallocf)
INTERPOSE(counting_valloc, valloc)
INTERPOSE(counting_aligned_alloc, aligned_alloc)
INTERPOSE(counting_posix_memalign, posix_memalign)
INTERPOSE(counting_malloc_zone_malloc, malloc_zone_malloc)
INTERPOSE(counting_malloc_zone_calloc, malloc_zone_calloc)
INTERPOSE(counting_malloc_zone_realloc, malloc_zone_realloc)
INTERPOSE(counting_malloc_zone_valloc, malloc_zone_valloc)
INTERPOSE(counting_malloc_zone_memalign, malloc_zone_memalign)
INTERPOSE(counting_malloc_zone_malloc_with_options, malloc_zone_malloc_with_options)
INTERPOSE(counting_malloc_type_malloc, malloc_type_malloc)
INTERPOSE(counting_malloc_type_calloc, malloc_type_calloc)
INTERPOSE(counting_malloc_type_realloc, malloc_type_realloc)
INTERPOSE(counting_malloc_type_valloc, malloc_type_valloc)
INTERPOSE(counting_malloc_type_aligned_alloc, malloc_type_aligned_alloc)
INTERPOSE(counting_malloc_type_posix_memalign, malloc_type_posix_memalign)
INTERPOSE(counting_malloc_type_zone_malloc, malloc_type_zone_malloc)
INTERPOSE(counting_malloc_type_zone_calloc, malloc_type_zone_calloc)
INTERPOSE(counting_malloc_type_zone_realloc, malloc_type_zone_realloc)
INTERPOSE(counting_malloc_type_zone_valloc, malloc_type_zone_valloc)
INTERPOSE(counting_malloc_type_zone_memalign, malloc_type_zone_memalign)
INTERPOSE(counting_malloc_type_zone_malloc_with_options, malloc_type_zone_malloc_with_options)

#elif defined(__GLIBC__)

// An executable's definitions of the allocator functions replace glibc's for
// the whole process, shared libraries such as the Swift runtime included.
// These forward to glibc's allocator under the `__libc_*` names it also
// exports it by, which never call back into these, so glibc's own `free` still
// releases the memory and each allocation counts once. Other C libraries, such
// as musl, export no such names, so they count no allocations.

#include <errno.h>
#include <malloc.h>

static inline bool is_power_of_two(size_t value) {
    return value != 0 && (value & (value - 1)) == 0;
}

extern void *__libc_malloc(size_t size);
extern void *__libc_calloc(size_t count, size_t size);
extern void *__libc_realloc(void *block, size_t size);
extern void *__libc_memalign(size_t alignment, size_t size);
extern void *__libc_valloc(size_t size);
extern void *__libc_pvalloc(size_t size);

void *malloc(size_t size) {
    count_allocation();
    return __libc_malloc(size);
}
void *calloc(size_t count, size_t size) {
    count_allocation();
    return __libc_calloc(count, size);
}
void *realloc(void *block, size_t size) {
    count_allocation();
    return __libc_realloc(block, size);
}
void *memalign(size_t alignment, size_t size) {
    count_allocation();
    return __libc_memalign(alignment, size);
}
void *aligned_alloc(size_t alignment, size_t size) {
    // glibc 2.38's check: a power of two.
    if (!is_power_of_two(alignment)) {
        errno = EINVAL;
        return NULL;
    }
    count_allocation();
    return __libc_memalign(alignment, size);
}
int posix_memalign(void **block, size_t alignment, size_t size) {
    // glibc's check: a power of two that is a multiple of the pointer size.
    if (!is_power_of_two(alignment) || alignment % sizeof(void *) != 0) {
        return EINVAL;
    }
    count_allocation();
    void *result = __libc_memalign(alignment, size);
    if (result == NULL) {
        return ENOMEM;
    }
    *block = result;
    return 0;
}
void *valloc(size_t size) {
    count_allocation();
    return __libc_valloc(size);
}
void *pvalloc(size_t size) {
    count_allocation();
    return __libc_pvalloc(size);
}

#endif
