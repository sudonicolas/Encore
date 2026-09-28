// Shifts the wall clock of the screenshot tool (and only it: it's injected with
// DYLD_INSERT_LIBRARIES) by ENCORE_STAGE_CLOCK_OFFSET seconds, so the screenshots are
// taken at 9:41 AM. "2 min. ago", the dates in a clipping's header and the drawn menu bar
// clock then all agree, whatever time the script runs. Monotonic clocks are untouched, so
// timers and animations run normally.

#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

static int64_t offset_seconds(void) {
    static int64_t offset;
    static int loaded;
    if (!loaded) {
        const char *value = getenv("ENCORE_STAGE_CLOCK_OFFSET");
        offset = value ? strtoll(value, NULL, 10) : 0;
        loaded = 1;
    }
    return offset;
}

static int stage_clock_gettime(clockid_t clock, struct timespec *tp) {
    int result = clock_gettime(clock, tp);
    if (result == 0 && tp && clock == CLOCK_REALTIME) tp->tv_sec += offset_seconds();
    return result;
}

static uint64_t stage_clock_gettime_nsec_np(clockid_t clock) {
    uint64_t ns = clock_gettime_nsec_np(clock);
    if (ns && clock == CLOCK_REALTIME) ns += (uint64_t)(offset_seconds() * 1000000000LL);
    return ns;
}

static int stage_gettimeofday(struct timeval *tv, void *tz) {
    int result = gettimeofday(tv, tz);
    if (result == 0 && tv) tv->tv_sec += offset_seconds();
    return result;
}

static time_t stage_time(time_t *out) {
    time_t now = time(NULL) + offset_seconds();
    if (out) *out = now;
    return now;
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } interposers[] = {
    { (const void *)stage_clock_gettime, (const void *)clock_gettime },
    { (const void *)stage_clock_gettime_nsec_np, (const void *)clock_gettime_nsec_np },
    { (const void *)stage_gettimeofday, (const void *)gettimeofday },
    { (const void *)stage_time, (const void *)time },
};
