// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2026 Egbert de Pauw
//
// anchorline_io: the C layer between libdivecomputer's blocking custom I/O
// and Dart.
//
// libdivecomputer calls an iostream's callbacks from one thread and expects
// them to block: a read waits until a packet arrives or the timeout passes.
// In the app that thread is the download isolate's. The Bluetooth connection
// lives on the main isolate, which cannot block. An al_link_t sits between
// the two:
//
// - The main isolate pushes every notification with al_link_push. A read
//   takes one packet per call, waiting on a condition variable.
// - A write, and a characteristic read or write, is a request. The link puts
//   it in a pending slot, calls the request callback (in the app a
//   NativeCallable.listener, which posts to the main isolate and returns at
//   once) and waits for al_link_complete. The main isolate takes the request
//   with al_link_pending, does it, and completes it.
// - al_link_cancel and al_link_disconnected wake whatever waits.
//
// A replay link serves a recording instead, in order, on demand.
//
// Recording layout. Big-endian events, one after another, each
//   u8 kind, u64 microseconds since the link was created (monotonic clock),
//   u32 length, then length bytes of payload:
//   'W' a write: the bytes written.
//   'R' a read: the bytes it returned.
//   'P' a purge of the input: u32 number of bytes dropped.
//   'C' a characteristic read or write: u8 direction (DC_IOCTL_DIR_READ or
//       DC_IOCTL_DIR_WRITE), u8 UUID length, the UUID as text (36 lower-case
//       characters), then the value read or written.
//   'I' an ioctl the link does not support: u32 the request.
//   'S' a sleep: u32 milliseconds.
//   'T' libdivecomputer set the read timeout: i32 milliseconds.
//   'X' anything else, as ASCII text: "configure 115200 8N1", "set_dtr 1",
//       "set_rts 0", "set_break 0", "overflow".
// A replay reads only R, W and C and skips the rest.
//
// Threads. The iostream's callbacks run on one thread at a time, as
// libdivecomputer calls them. The functions for the main isolate (push,
// pending, complete, disconnected, cancel, cancelled, the setters and
// al_link_recording) are thread-safe and never wait for the other side.
// al_link_iostream and al_link_free are for the owner, while no callback
// runs.

#ifndef ANCHORLINE_IO_H
#define ANCHORLINE_IO_H

#include <stddef.h>
#include <stdint.h>

#include <libdivecomputer/common.h>
#include <libdivecomputer/context.h>
#include <libdivecomputer/iostream.h>

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

/* The kinds of request the request callback announces. */
#define AL_REQ_WRITE 1
#define AL_REQ_CHAR_READ 2
#define AL_REQ_CHAR_WRITE 3

/* The most unread bytes a live link holds. One more is an overflow. */
#define AL_LINK_QUEUE_LIMIT (8 * 1024 * 1024)

/* The write timeout a new live link starts with, in milliseconds. */
#define AL_LINK_WRITE_TIMEOUT 10000

typedef struct al_link al_link_t;

/*
 * Called from the blocking thread when a request is waiting. `link` is the
 * al_link_t, `kind` one of AL_REQ_*. It must not block and must not rely on
 * anything being done when it returns.
 */
typedef void (*al_request_fn) (intptr_t link, int32_t kind);

/*
 * A live link. `advertised_name` (copied; NULL when there is none) answers
 * DC_IOCTL_BLE_GET_NAME. `request` must stay callable until every iostream
 * of the link is closed. Returns NULL when `request` is NULL or memory runs
 * out.
 */
al_link_t *
al_link_new_live (const char *advertised_name, al_request_fn request);

/*
 * A replay link that serves `events` (copied), in the recording layout.
 * Returns NULL when the layout runs past `size` or memory runs out.
 */
al_link_t *
al_link_new_replay (const char *advertised_name, const uint8_t *events, size_t size);

/*
 * Frees the link. Close every iostream of the link first, and make sure
 * nothing calls any other al_link_* function on it any more.
 */
void
al_link_free (al_link_t *link);

/*
 * Opens a DC_TRANSPORT_BLE custom iostream on the link, for dc_device_open.
 * `context` may be NULL; a replay logs a divergence to it. Closing the
 * iostream closes the link: later reads and writes return DC_STATUS_IO,
 * until another al_link_iostream.
 */
dc_status_t
al_link_iostream (al_link_t *link, dc_context_t *context, dc_iostream_t **out);

/*
 * Appends one received packet to a live link's inbound queue. Ignored after
 * a disconnect, a close or an overflow. When the queue would hold more than
 * AL_LINK_QUEUE_LIMIT bytes, the link drops it, records X "overflow", and
 * every later read returns DC_STATUS_IO.
 */
void
al_link_push (al_link_t *link, const uint8_t *data, size_t size);

/*
 * Takes the request waiting in the pending slot. Copies its bytes (what to
 * write; nothing for a characteristic read) into `data`, and the UUID of a
 * characteristic request into `uuid` (36 characters and a NUL; an empty
 * string for a plain write), and returns the number of bytes.
 *
 * When the bytes do not fit in `capacity`, copies nothing, takes nothing and
 * returns the size needed. `data` may be NULL only with `capacity` 0.
 * `uuid` must hold DC_BLE_UUID_SIZE bytes: with less, a characteristic
 * request is not taken.
 *
 * When no request is waiting to be taken (none was made, it was taken
 * already, or it timed out), returns 0 and stores an empty string in `uuid`.
 * A write of zero bytes never makes a request, so 0 with an empty `uuid`
 * always means nothing to do.
 *
 * A request is taken once. Only a taken request can be completed, so a
 * completion meant for an earlier request that timed out never completes a
 * later one, provided the caller completes each request it took before it
 * takes the next.
 */
size_t
al_link_pending (al_link_t *link, uint8_t *data, size_t capacity, char *uuid, size_t uuid_capacity);

/*
 * Completes the taken request with `status`, and wakes the blocking thread.
 * For a characteristic read, `data` is the value: it is copied after the
 * UUID in the ioctl buffer, and a value that does not fit there turns the
 * result into DC_STATUS_INVALIDARGS. Ignored when no taken request is
 * waiting.
 */
void
al_link_complete (al_link_t *link, dc_status_t status, const uint8_t *data, size_t size);

/*
 * The connection dropped. Wakes the blocking thread: a waiting write returns
 * DC_STATUS_IO, and a read returns what is still queued, then DC_STATUS_IO.
 */
void
al_link_disconnected (al_link_t *link);

/*
 * Cancels the download. Every waiting or later read, write, poll and sleep
 * returns DC_STATUS_CANCELLED at once, and al_link_cancelled returns 1.
 */
void
al_link_cancel (al_link_t *link);

/*
 * 1 after al_link_cancel, otherwise 0. Takes the link as `void *` so that it
 * can be given to dc_device_set_cancel as it is.
 */
int
al_link_cancelled (void *link);

/*
 * How long a write or a characteristic request waits for al_link_complete
 * before it returns DC_STATUS_TIMEOUT. A negative value waits until the
 * completion, a cancel or a disconnect. The default is AL_LINK_WRITE_TIMEOUT.
 */
void
al_link_set_write_timeout (al_link_t *link, int milliseconds);

/*
 * Turns recording on (nonzero) or off. While it is off nothing is added; what
 * was recorded stays.
 */
void
al_link_set_recording (al_link_t *link, int enabled);

/*
 * Copies the recording into `data` and returns its size. When it does not
 * fit in `capacity`, copies nothing and returns the size needed.
 */
size_t
al_link_recording (al_link_t *link, uint8_t *data, size_t capacity);

/*
 * The index of the next event a replay link will serve, counting every event
 * of the recording from 0. After a divergence (a write that differs, or a
 * read where the recording has something else) it stays at the event that
 * diverged. -1 for a live link.
 */
int
al_link_replay_position (al_link_t *link);

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* ANCHORLINE_IO_H */
