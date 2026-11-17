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
//   with al_link_pending, which hands out its id and kind, does it, and
//   completes it by that id. Handlers may interleave: an id that is no longer
//   the waiting request completes nothing.
// - al_link_cancel and al_link_disconnected wake whatever waits.
//
// A replay link serves a recording instead, in order, on demand.
//
// Recording layout. Big-endian events, one after another, each
//   u8 kind, u64 microseconds since the link was created (monotonic clock),
//   u32 length, then length bytes of payload:
//   'W' a write, when it is issued: the bytes written.
//   'R' a read: the bytes it returned. Length 0: the read returned nothing,
//       because it timed out or failed.
//   'P' a purge of the input: u32 number of bytes dropped.
//   'C' a characteristic read or write: u8 direction (DC_IOCTL_DIR_READ or
//       DC_IOCTL_DIR_WRITE), u8 UUID length, the UUID as text (36 lower-case
//       characters), then the value read (nothing when the read failed) or
//       written. A write is recorded when it is issued, a read when it ends.
//   'E' the read, write or characteristic request just before it failed:
//       i32 its dc_status_t (DC_STATUS_TIMEOUT is -7). A call that succeeded
//       has no E. Only skipped events (an X overflow, say) can come between.
//   'I' an ioctl the link does not support: u32 the request.
//   'S' a sleep: u32 milliseconds.
//   'T' libdivecomputer set the read timeout: i32 milliseconds.
//   'X' anything else, as ASCII text: "configure 115200 8N1", "set_dtr 1",
//       "set_rts 0", "set_break 0", "overflow".
// A replay serves R, W and C in order and skips the rest, except that the E
// after a W, a C or an empty R gives that call's status: a read that timed
// out live times out again, and so does a write. An empty R without an E
// times out. E and the empty R were added before any recording left the
// project; recordings without them replay as before, and a replayer that
// does not know them sees an empty read and skips the E.
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
 * DC_IOCTL_BLE_GET_NAME, truncated to the caller's buffer and always
 * NUL-terminated; with no name that ioctl is DC_STATUS_UNSUPPORTED.
 * `request` must stay callable until every iostream of the link is closed.
 * Returns NULL when `request` is NULL or memory runs out.
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
 * Takes the request waiting in the pending slot, for the main isolate to
 * carry out. Three outcomes, told apart by `*request_id`:
 *
 * - Taken: `*request_id` is the request's id, greater than 0, and `*kind` its
 *   AL_REQ_* kind. Its bytes (what to write; nothing for a characteristic
 *   read) are copied into `data`, and the UUID of a characteristic request
 *   into `uuid` (36 lower-case characters and a NUL; an empty string for a
 *   plain write). Returns the number of bytes copied, which may be 0 for a
 *   characteristic request.
 *
 * - A buffer is too small: `data` cannot hold the bytes, or `uuid` holds less
 *   than DC_BLE_UUID_SIZE bytes for a characteristic request. Nothing is
 *   copied or taken. `*request_id` is -1 and `*kind` the request's kind.
 *   Returns the number of bytes `data` must hold; call again with that, and
 *   with DC_BLE_UUID_SIZE bytes of `uuid`.
 *
 * - Nothing to take: no request is waiting, it was taken already, or it
 *   finished. `*request_id` and `*kind` are 0, `uuid` is an empty string,
 *   and it returns 0.
 *
 * `data` may be NULL only with `capacity` 0. `request_id` must not be NULL:
 * without it nothing is taken. `kind` may be NULL. A request is taken once.
 *
 * Use this kind, not the one the request callback announced: a notification
 * handled after its own request timed out can take a newer request of
 * another kind.
 */
size_t
al_link_pending (al_link_t *link, uint8_t *data, size_t capacity, char *uuid, size_t uuid_capacity, int64_t *request_id, int32_t *kind);

/*
 * Completes request `request_id` (from al_link_pending) with `status`, and
 * wakes the blocking thread. For a characteristic read, `data` is the value:
 * it is copied after the UUID in the ioctl buffer, and a value that does not
 * fit there turns the result into DC_STATUS_INVALIDARGS.
 *
 * Applies only when `request_id` is the request the blocking thread waits
 * for, taken and not yet completed. Anything else is ignored: an id of 0 or
 * -1, a request that timed out or was completed already, or one that is not
 * the current request because handlers finished out of order. Ids never
 * repeat, so a completion can never land on another request.
 */
void
al_link_complete (al_link_t *link, int64_t request_id, dc_status_t status, const uint8_t *data, size_t size);

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
 * of the recording from 0. After a divergence it stays at the event that
 * diverged: a write that differs (DC_STATUS_PROTOCOL), a read or a request
 * where the recording has something else (DC_STATUS_PROTOCOL), or a
 * recorded characteristic value longer than the caller's buffer
 * (DC_STATUS_INVALIDARGS). -1 for a live link.
 */
int
al_link_replay_position (al_link_t *link);

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* ANCHORLINE_IO_H */
