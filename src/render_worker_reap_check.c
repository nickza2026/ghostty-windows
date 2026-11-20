/* Private deterministic CPU-only seam. No child process, HWND, GPU, real wait,
 * job mutation, process discovery or driver calls. Compile as GUI subsystem.
 * Include production implementation; replace only the reap boundary APIs. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static ULONGLONG clock_ms, wait_elapsed, empty_at;
static DWORD wait_result, child_code, query_error, sleep_overshoot;
static unsigned waits, queries, sleeps, late_queries, overlong_sleep_requests;
static DWORD last_sleep;
static int exit_query_ok;
static ULONGLONG WINAPI check_tick(void) { return clock_ms; }
static DWORD WINAPI check_wait(HANDLE h, DWORD budget) {
    (void)h; (void)budget; ++waits; clock_ms += wait_elapsed;
    if (wait_result == WAIT_FAILED) SetLastError(ERROR_INVALID_HANDLE);
    return wait_result;
}
static BOOL WINAPI check_exit(HANDLE h, LPDWORD code) {
    (void)h; *code = child_code;
    if (!exit_query_ok) SetLastError(ERROR_ACCESS_DENIED);
    return exit_query_ok;
}
static BOOL WINAPI check_job(HANDLE h, JOBOBJECTINFOCLASS kind,
                           LPVOID out, DWORD size, LPDWORD returned) {
    (void)h; (void)kind; (void)size; (void)returned;
    ++queries; if (clock_ms > 50) ++late_queries;
    if (query_error) { SetLastError(query_error); return FALSE; }
    memset(out, 0, sizeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
    ((JOBOBJECT_BASIC_ACCOUNTING_INFORMATION *)out)->ActiveProcesses =
        clock_ms < empty_at ? 1 : 0;
    return TRUE;
}
static void WINAPI check_sleep(DWORD delay) {
    if (clock_ms >= 50 || delay > 50-clock_ms) ++overlong_sleep_requests;
    last_sleep = delay;
    ++sleeps; clock_ms += delay + sleep_overshoot;
}
#define GetTickCount64 check_tick
#define WaitForSingleObject check_wait
#define GetExitCodeProcess check_exit
#define QueryInformationJobObject check_job
#define Sleep check_sleep
#include "render_worker_client.c"
#undef GetTickCount64
#undef WaitForSingleObject
#undef GetExitCodeProcess
#undef QueryInformationJobObject
#undef Sleep

static void reset(RwClient *c, RwStatus *s) {
    memset(c, 0, sizeof(*c)); memset(s, 0, sizeof(*s));
    /* These sentinels are consumed only by the private boundary stubs. */
    c->process = (HANDLE)(uintptr_t)1; c->job = (HANDLE)(uintptr_t)2;
    c->close_ack = 1; s->close_ack = 1; s->child_exit = STILL_ACTIVE;
    clock_ms = wait_elapsed = empty_at = 0;
    wait_result = WAIT_OBJECT_0; child_code = query_error = sleep_overshoot = 0;
    waits = queries = sleeps = late_queries = overlong_sleep_requests = 0;
    last_sleep = 0; exit_query_ok = 1;
}
static int require(int condition, const char *name) {
    condition = condition && !overlong_sleep_requests;
    printf("%s %s clock=%llu waits=%u queries=%u sleeps=%u late_queries=%u last_sleep=%lu overlong_sleep_requests=%u\n",
           condition ? "PASS" : "FAIL", name, (unsigned long long)clock_ms,
           waits, queries, sleeps, late_queries, (unsigned long)last_sleep, overlong_sleep_requests);
    return !condition;
}
int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR args, int show) {
    (void)instance; (void)previous; (void)args; (void)show;
    RwClient c; RwStatus s; int failed = 0, result;
    reset(&c, &s);
    result = rw_finish(&c, 50, &s);
    failed += require(result == 1 && c.finished && s.close_ack &&
        s.process_exited && s.child_exit == 0 && s.job_empty && !s.forced && !sleeps,
        "already-empty-natural-close");
    reset(&c, &s); empty_at = 20;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 1 && clock_ms == 20 && s.job_empty,
        "job-drains-within-original-budget");
    reset(&c, &s); wait_elapsed = 49; empty_at = 51;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && !c.finished && !s.job_empty &&
        s.close_ack && s.process_exited && s.child_exit == 0 && !s.forced,
        "must-not-promote-job-empty-after-budget");
    reset(&c, &s); wait_elapsed = 40; empty_at = 51; sleep_overshoot = 11;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && !c.finished && !late_queries,
        "scheduler-oversleep-must-not-trigger-late-poll-or-success");
    reset(&c, &s); wait_result = WAIT_TIMEOUT; wait_elapsed = 50;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && !s.process_exited && !queries && !c.finished,
        "process-timeout-is-not-healthy");
    reset(&c, &s); wait_result = WAIT_FAILED;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && !s.process_exited && !queries,
        "process-wait-failure-is-not-healthy");
    reset(&c, &s); exit_query_ok = 0;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && !s.process_exited && !queries,
        "exit-query-failure-is-not-healthy");
    reset(&c, &s); query_error = ERROR_ACCESS_DENIED;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && !s.job_empty && !c.finished,
        "job-query-failure-is-not-empty");
    reset(&c, &s); child_code = 77;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && s.process_exited && s.child_exit == 77 &&
        s.job_empty && !c.finished, "nonzero-child-exit-is-not-healthy");
    reset(&c, &s); c.close_ack = 0; s.close_ack = 0;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && !waits && !queries,
        "missing-ack-rejected-before-wait");
    reset(&c, &s);
    result = rw_finish(&c, 0, &s);
    failed += require(result == 0 && !waits && !queries,
        "finish-zero-budget-rejected");
    reset(&c, &s); wait_elapsed = 60;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 1 && queries == 1 && !sleeps && s.job_empty,
        "process-wait-scheduling-delay-keeps-immediate-empty-probe");
    reset(&c, &s);
    result = reap(&c, 0, &s);
    failed += require(result == 1 && queries == 1 && !sleeps,
        "zero-budget-reap-keeps-nonblocking-ready-check");
    reset(&c, &s); wait_elapsed = 49; empty_at = 50;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 1 && clock_ms == 50 && s.job_empty && last_sleep == 1,
        "ready-exactly-at-deadline-keeps-zero-wait-probe-and-clamped-sleep");
    reset(&c, &s); wait_elapsed = 50; empty_at = 51;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && queries == 1 && !sleeps && !s.job_empty,
        "active-at-deadline-does-not-get-more-wait");
    reset(&c, &s); wait_elapsed = 60; empty_at = 61;
    result = rw_finish(&c, 50, &s);
    failed += require(result == 0 && queries == 1 && !sleeps && !s.job_empty,
        "late-scheduled-initial-probe-cannot-wait-for-still-active-job");
    printf("CPU_REAP_RESULT cases=16 failed=%d historical_gpu_failures_resolved=0\n", failed);
    return failed ? 1 : 0;
}
