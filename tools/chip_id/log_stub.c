/*
 * Stub implementation of log_hal for standalone chip_id tool
 * The libloragw library is compiled with -DSTATIONLOG which requires
 * this logging function from Basic Station. This stub provides a
 * minimal implementation for chip_id to link successfully.
 */

#include <stdio.h>
#include <stdarg.h>

void log_hal(int level, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}
