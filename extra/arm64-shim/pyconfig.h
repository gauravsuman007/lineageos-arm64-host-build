#if __has_include(<internal/pycore_pystate.h>)
#include "../cpython3/android/linux_x86_64/pyconfig/pyconfig.h"
#else
#include "../cpython2/linux_x86_64/pyconfig/pyconfig.h"
#endif

/* arm64 host overrides of the x86_64 pyconfig */
#undef HAVE_GCC_ASM_FOR_X87
#undef HAVE_GCC_ASM_FOR_X64
#undef VA_LIST_IS_ARRAY
#undef HAVE_STROPTS_H
#ifndef SOABI
#define SOABI "cpython-38android-x86_64-linux-gnu"
#endif
