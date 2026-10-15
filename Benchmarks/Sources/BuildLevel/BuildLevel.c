#include "BuildLevel.h"

bool build_level_is_below_x86_64_v3(void) {
#if defined(__x86_64__) || defined(_M_X64)
    // x86-64-v3 adds these to x86-64-v2; AVX2 implies AVX and the v2 set.
#if defined(__AVX2__) && defined(__BMI__) && defined(__BMI2__) && defined(__F16C__) \
    && defined(__FMA__) && defined(__LZCNT__) && defined(__MOVBE__)
    return false;
#else
    return true;
#endif
#else
    return false;
#endif
}
