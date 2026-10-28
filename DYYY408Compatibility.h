#ifndef DYYY408COMPATIBILITY_H
#define DYYY408COMPATIBILITY_H

#ifdef __cplusplus
extern "C" {
#endif

// Runtime-only diagnostic: never modifies host properties or calls private APIs.
void DYYY408ScheduleRuntimeCompatibilityReport(void);

#ifdef __cplusplus
}
#endif

#endif
