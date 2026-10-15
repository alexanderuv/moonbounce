// Which instruction-set level the benchmarks were compiled for.
//
// x86-64 figures count only from an x86-64-v3 build (docs/validation.md,
// x86-64 instruction set). Swift can't test target features, but `-Xcc
// -march` sets them for this C target and the Swift modules alike, so the
// compiler's predefined macros here describe the whole build.

#ifndef BENCHMARKS_BUILD_LEVEL_H
#define BENCHMARKS_BUILD_LEVEL_H

#include <stdbool.h>

/// True on x86-64 when the build targets less than x86-64-v3; false at
/// x86-64-v3 or above, and on every other architecture.
bool build_level_is_below_x86_64_v3(void);

#endif
