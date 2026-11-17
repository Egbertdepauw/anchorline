// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2026 Egbert de Pauw
//
// al_thread.h: the mutex, condition variable, monotonic clock and sleep that
// anchorline_io.c needs, on pthreads (POSIX) and on SRWLOCK and
// CONDITION_VARIABLE (Windows).
//
// Every function is static, so none of them is exported from the library,
// and none of them reads the wall clock. A timed wait takes a relative
// duration; the caller measures its deadline with al_monotonic_us() and calls
// the wait in a loop on its predicate, so an early or spurious wakeup only
// costs one more turn of that loop.
//
// This header is private to the C layer. It is not an ffigen entry point.

#ifndef AL_THREAD_H
#define AL_THREAD_H

#include <stdint.h>

#if defined(_MSC_VER) && !defined(__cplusplus)
#define AL_INLINE __inline
#else
#define AL_INLINE inline
#endif

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
// wingdi.h defines ERROR, which libdivecomputer's context-private.h defines
// as a logging macro.
#ifndef NOGDI
#define NOGDI
#endif
#include <windows.h>

typedef SRWLOCK al_mutex_t;
typedef CONDITION_VARIABLE al_cond_t;

// SRWLOCK and CONDITION_VARIABLE need no resources, so init cannot fail and
// destroy has nothing to do.
static AL_INLINE int
al_mutex_init (al_mutex_t *mutex)
{
	InitializeSRWLock (mutex);
	return 0;
}

static AL_INLINE void
al_mutex_destroy (al_mutex_t *mutex)
{
	(void) mutex;
}

static AL_INLINE void
al_mutex_lock (al_mutex_t *mutex)
{
	AcquireSRWLockExclusive (mutex);
}

static AL_INLINE void
al_mutex_unlock (al_mutex_t *mutex)
{
	ReleaseSRWLockExclusive (mutex);
}

static AL_INLINE int
al_cond_init (al_cond_t *cond)
{
	InitializeConditionVariable (cond);
	return 0;
}

static AL_INLINE void
al_cond_destroy (al_cond_t *cond)
{
	(void) cond;
}

static AL_INLINE void
al_cond_broadcast (al_cond_t *cond)
{
	WakeAllConditionVariable (cond);
}

static AL_INLINE void
al_cond_wait (al_cond_t *cond, al_mutex_t *mutex)
{
	SleepConditionVariableSRW (cond, mutex, INFINITE, 0);
}

// Waits at most `microseconds`, rounded up to whole milliseconds so that a
// short remainder does not turn into a busy loop. A timeout reports FALSE
// with ERROR_TIMEOUT; the caller's loop tells the cases apart by its own
// predicate and deadline.
static AL_INLINE void
al_cond_timedwait (al_cond_t *cond, al_mutex_t *mutex, uint64_t microseconds)
{
	uint64_t milliseconds = (microseconds + 999) / 1000;
	// INFINITE is 0xFFFFFFFF; stay well below it.
	if (milliseconds > 0x7FFFFFFF)
		milliseconds = 0x7FFFFFFF;
	SleepConditionVariableSRW (cond, mutex, (DWORD) milliseconds, 0);
}

// QueryPerformanceCounter is monotonic and never fails on Windows XP and
// later. Split into whole seconds and the rest so the multiplication cannot
// overflow.
static AL_INLINE uint64_t
al_monotonic_us (void)
{
	LARGE_INTEGER frequency, counter;
	QueryPerformanceFrequency (&frequency);
	QueryPerformanceCounter (&counter);
	uint64_t f = (uint64_t) frequency.QuadPart;
	uint64_t c = (uint64_t) counter.QuadPart;
	return (c / f) * 1000000u + (c % f) * 1000000u / f;
}

static AL_INLINE void
al_sleep_ms (unsigned int milliseconds)
{
	Sleep (milliseconds);
}

#else /* POSIX */

#include <errno.h>
#include <pthread.h>
#include <time.h>

typedef pthread_mutex_t al_mutex_t;
typedef pthread_cond_t al_cond_t;

static AL_INLINE int
al_mutex_init (al_mutex_t *mutex)
{
	return pthread_mutex_init (mutex, NULL);
}

static AL_INLINE void
al_mutex_destroy (al_mutex_t *mutex)
{
	pthread_mutex_destroy (mutex);
}

static AL_INLINE void
al_mutex_lock (al_mutex_t *mutex)
{
	pthread_mutex_lock (mutex);
}

static AL_INLINE void
al_mutex_unlock (al_mutex_t *mutex)
{
	pthread_mutex_unlock (mutex);
}

// Apple has no pthread_condattr_setclock; its timed wait below is relative
// instead. Everywhere else the condition variable measures its absolute
// deadline on CLOCK_MONOTONIC, not on the default CLOCK_REALTIME.
static AL_INLINE int
al_cond_init (al_cond_t *cond)
{
#if defined(__APPLE__)
	return pthread_cond_init (cond, NULL);
#else
	pthread_condattr_t attr;
	int rc = pthread_condattr_init (&attr);
	if (rc != 0)
		return rc;
	rc = pthread_condattr_setclock (&attr, CLOCK_MONOTONIC);
	if (rc == 0)
		rc = pthread_cond_init (cond, &attr);
	pthread_condattr_destroy (&attr);
	return rc;
#endif
}

static AL_INLINE void
al_cond_destroy (al_cond_t *cond)
{
	pthread_cond_destroy (cond);
}

static AL_INLINE void
al_cond_broadcast (al_cond_t *cond)
{
	pthread_cond_broadcast (cond);
}

static AL_INLINE void
al_cond_wait (al_cond_t *cond, al_mutex_t *mutex)
{
	pthread_cond_wait (cond, mutex);
}

// Waits at most `microseconds`. ETIMEDOUT and EINTR need no handling: the
// caller's loop re-checks its predicate and its monotonic deadline.
static AL_INLINE void
al_cond_timedwait (al_cond_t *cond, al_mutex_t *mutex, uint64_t microseconds)
{
	struct timespec ts;
#if defined(__APPLE__)
	ts.tv_sec = (time_t) (microseconds / 1000000u);
	ts.tv_nsec = (long) (microseconds % 1000000u) * 1000;
	pthread_cond_timedwait_relative_np (cond, mutex, &ts);
#else
	clock_gettime (CLOCK_MONOTONIC, &ts);
	uint64_t nanoseconds = (uint64_t) ts.tv_nsec + (microseconds % 1000000u) * 1000u;
	ts.tv_sec += (time_t) (microseconds / 1000000u) + (time_t) (nanoseconds / 1000000000u);
	ts.tv_nsec = (long) (nanoseconds % 1000000000u);
	pthread_cond_timedwait (cond, mutex, &ts);
#endif
}

static AL_INLINE uint64_t
al_monotonic_us (void)
{
	struct timespec ts;
	clock_gettime (CLOCK_MONOTONIC, &ts);
	return (uint64_t) ts.tv_sec * 1000000u + (uint64_t) ts.tv_nsec / 1000u;
}

static AL_INLINE void
al_sleep_ms (unsigned int milliseconds)
{
	struct timespec ts;
	ts.tv_sec = (time_t) (milliseconds / 1000);
	ts.tv_nsec = (long) (milliseconds % 1000) * 1000000;
	while (nanosleep (&ts, &ts) != 0 && errno == EINTR) {
		// Interrupted by a signal: sleep for what is left.
	}
}

#endif /* _WIN32 */

#endif /* AL_THREAD_H */
