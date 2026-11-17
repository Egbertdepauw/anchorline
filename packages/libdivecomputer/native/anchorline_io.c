// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2026 Egbert de Pauw
//
// anchorline_io.c: the C layer between libdivecomputer's blocking custom I/O
// and Dart. The interface and the recording layout are in anchorline_io.h.
//
// Concurrency
//
// One mutex, `lock`, guards every field of a link that can change after
// creation. One condition variable, `cond`, is broadcast on every change that
// a waiter can wait for: a packet, a completion, a cancel, a disconnect, a
// close. Only the blocking thread (libdivecomputer's, in the app the download
// isolate's) ever waits, and it always waits in a loop on its predicate, so a
// spurious or early wakeup costs one more turn and a broadcast that comes
// before the wait is never lost: the predicate is checked under the lock
// before every wait. Timed waits are measured against a deadline on the
// monotonic clock.
//
// Nothing leaves the layer with the lock held: the request callback and
// libdivecomputer's log are called after unlocking. A callback that calls
// back into the link therefore cannot deadlock, and there is no second lock,
// so there is no lock order to get wrong.
//
// Requests
//
// A write, a characteristic read and a characteristic write are requests.
// Each gets a sequence number, `req_seq`, nonzero while it is in the pending
// slot, which is also its request id. al_link_pending takes it by setting
// `taken_seq` to that number and hands the id out with the request's kind;
// al_link_complete takes the id back and completes the request only when the
// id is the request in the slot, taken and not done. When the request
// finishes (completed, timed out, cancelled or disconnected), the blocking
// thread empties the slot. Ids never repeat, so however the main isolate's
// handlers interleave:
// - a completion with nothing pending finds req_seq 0 and is ignored;
// - a late completion of a request that timed out carries an id that is no
//   longer in the slot, and is ignored, even when a newer request was taken
//   in the meantime;
// - a duplicate completion finds the request done, and is ignored;
// - a notification for a request that already timed out finds nothing to
//   take, or takes the newer request together with that request's own kind
//   and id.
// The blocking thread is the only one that fills or empties the slot, and it
// does so with the lock held.
//
// Helpers private to this file are static and none is named al_*, so the
// Windows export scan (lib/src/hook/build_config.dart) finds only the API.

#include <stdlib.h>
#include <string.h>

// First: on Windows it includes windows.h with NOGDI, before
// context-private.h defines ERROR.
#include "al_thread.h"

#include <libdivecomputer/ble.h>
#include <libdivecomputer/custom.h>
#include <libdivecomputer/ioctl.h>

#include "anchorline_io.h"
#include "context-private.h"

// u8 kind, u64 microseconds, u32 length.
#define EVENT_HEADER 13

#define UUID_LENGTH (DC_BLE_UUID_SIZE - 1)

typedef struct packet_t {
	struct packet_t *next;
	size_t size;
	// Bytes already read; the rest stays at the head for the next read.
	size_t offset;
	unsigned char *data;
} packet_t;

typedef struct buffer_t {
	unsigned char *data;
	size_t size;
	size_t capacity;
} buffer_t;

// The next event of a replay that is an R, a W or a C.
typedef struct event_t {
	unsigned char kind;
	const unsigned char *payload;
	size_t size;
} event_t;

struct al_link {
	// Fixed at creation; read without the lock.
	int replay;
	char *name;
	al_request_fn request;
	uint64_t origin;
	unsigned char *events;
	size_t events_size;

	al_mutex_t lock;
	al_cond_t cond;

	// Everything below is guarded by lock.
	dc_context_t *context;
	int timeout;
	int write_timeout;
	int cancelled;
	int disconnected;
	int closed;
	int overflowed;

	// The inbound queue of a live link.
	packet_t *head;
	packet_t *tail;
	size_t queued;

	// The pending slot of a live link.
	uint64_t next_seq;
	uint64_t req_seq;
	uint64_t taken_seq;
	int32_t req_kind;
	int req_done;
	dc_status_t req_status;
	buffer_t req_data;
	char req_uuid[DC_BLE_UUID_SIZE];
	// A characteristic read: where the value goes, its room and its size.
	unsigned char *req_value;
	size_t req_value_capacity;
	size_t req_value_size;

	int recording;
	buffer_t rec;

	// A replay: the byte offset and index of the next event, and how much of
	// it (an R) was served already.
	size_t rp_offset;
	int rp_index;
	size_t rp_consumed;
};

// ---------------------------------------------------------------------------
// Bytes

static void
put_u32 (unsigned char *p, uint32_t value)
{
	p[0] = (unsigned char) (value >> 24);
	p[1] = (unsigned char) (value >> 16);
	p[2] = (unsigned char) (value >> 8);
	p[3] = (unsigned char) value;
}

static void
put_u64 (unsigned char *p, uint64_t value)
{
	put_u32 (p, (uint32_t) (value >> 32));
	put_u32 (p + 4, (uint32_t) value);
}

static uint32_t
get_u32 (const unsigned char *p)
{
	return ((uint32_t) p[0] << 24) | ((uint32_t) p[1] << 16) |
		((uint32_t) p[2] << 8) | (uint32_t) p[3];
}

// Makes room for `extra` more bytes. Returns 0 when memory runs out.
static int
buffer_reserve (buffer_t *buffer, size_t extra)
{
	if (extra > SIZE_MAX - buffer->size)
		return 0;
	size_t needed = buffer->size + extra;
	if (needed <= buffer->capacity)
		return 1;
	size_t capacity = buffer->capacity ? buffer->capacity : 256;
	while (capacity < needed) {
		if (capacity > SIZE_MAX / 2) {
			capacity = needed;
			break;
		}
		capacity *= 2;
	}
	unsigned char *data = (unsigned char *) realloc (buffer->data, capacity);
	if (data == NULL)
		return 0;
	buffer->data = data;
	buffer->capacity = capacity;
	return 1;
}

// Appends after buffer_reserve made room.
static void
buffer_put (buffer_t *buffer, const void *data, size_t size)
{
	if (size == 0)
		return;
	memcpy (buffer->data + buffer->size, data, size);
	buffer->size += size;
}

static int
ascii_equal_ignoring_case (const unsigned char *a, const char *b, size_t size)
{
	for (size_t i = 0; i < size; i++) {
		unsigned char x = a[i], y = (unsigned char) b[i];
		if (x >= 'A' && x <= 'Z')
			x = (unsigned char) (x - 'A' + 'a');
		if (y >= 'A' && y <= 'Z')
			y = (unsigned char) (y - 'A' + 'a');
		if (x != y)
			return 0;
	}
	return 1;
}

// ---------------------------------------------------------------------------
// Recording. All of these run with the lock held.

// Appends one event whose payload is `a` then `b`. An event that does not
// fit in memory is dropped whole, so the layout stays readable.
static void
record (al_link_t *link, unsigned char kind, const void *a, size_t asize, const void *b, size_t bsize)
{
	if (!link->recording)
		return;
	if (asize > 0xFFFFFFFFu || bsize > 0xFFFFFFFFu - asize)
		return;
	size_t length = asize + bsize;
	if (!buffer_reserve (&link->rec, EVENT_HEADER + length))
		return;
	unsigned char header[EVENT_HEADER];
	header[0] = kind;
	put_u64 (header + 1, al_monotonic_us () - link->origin);
	put_u32 (header + 9, (uint32_t) length);
	buffer_put (&link->rec, header, sizeof (header));
	buffer_put (&link->rec, a, asize);
	buffer_put (&link->rec, b, bsize);
}

static void
record_u32 (al_link_t *link, unsigned char kind, uint32_t value)
{
	unsigned char payload[4];
	put_u32 (payload, value);
	record (link, kind, payload, sizeof (payload), NULL, 0);
}

static void
record_text (al_link_t *link, const char *text)
{
	record (link, 'X', text, strlen (text), NULL, 0);
}

static void
record_characteristic (al_link_t *link, unsigned int direction, const char *uuid, const void *value, size_t size)
{
	unsigned char prefix[2 + UUID_LENGTH];
	prefix[0] = (unsigned char) direction;
	prefix[1] = UUID_LENGTH;
	memcpy (prefix + 2, uuid, UUID_LENGTH);
	record (link, 'C', prefix, sizeof (prefix), value, size);
}

// After the R, W or C of a call that failed: E with its status.
static void
record_result (al_link_t *link, dc_status_t status)
{
	if (status != DC_STATUS_SUCCESS)
		record_u32 (link, 'E', (uint32_t) status);
}

// A read that returned nothing: an R of length 0, then its status.
static void
record_failed_read (al_link_t *link, dc_status_t status)
{
	record (link, 'R', NULL, 0, NULL, 0);
	record_result (link, status);
}

// ---------------------------------------------------------------------------
// The live link. All of these run with the lock held.

static void
queue_clear (al_link_t *link)
{
	packet_t *packet = link->head;
	while (packet != NULL) {
		packet_t *next = packet->next;
		free (packet);
		packet = next;
	}
	link->head = NULL;
	link->tail = NULL;
	link->queued = 0;
}

// Waits until a packet is at the head of the queue, `timeout` milliseconds
// pass (negative: no limit; 0: no wait), or the link can no longer deliver
// one. Returns SUCCESS with a packet at the head, or what a read returns.
static dc_status_t
wait_for_packet (al_link_t *link, int timeout)
{
	uint64_t deadline = 0;
	if (timeout > 0)
		deadline = al_monotonic_us () + (uint64_t) timeout * 1000u;

	for (;;) {
		if (link->cancelled)
			return DC_STATUS_CANCELLED;
		if (link->overflowed || link->closed)
			return DC_STATUS_IO;
		if (link->head != NULL)
			return DC_STATUS_SUCCESS;
		// What arrived before a disconnect is still read, above.
		if (link->disconnected)
			return DC_STATUS_IO;
		if (timeout == 0)
			return DC_STATUS_TIMEOUT;
		if (timeout < 0) {
			al_cond_wait (&link->cond, &link->lock);
		} else {
			uint64_t now = al_monotonic_us ();
			if (now >= deadline)
				return DC_STATUS_TIMEOUT;
			al_cond_timedwait (&link->cond, &link->lock, deadline - now);
		}
	}
}

// Whether a request can be made at all.
static dc_status_t
request_gate (al_link_t *link)
{
	if (link->cancelled)
		return DC_STATUS_CANCELLED;
	if (link->disconnected || link->closed)
		return DC_STATUS_IO;
	return DC_STATUS_SUCCESS;
}

// Fills the pending slot, announces the request and waits until it is
// completed, the write timeout passes, or the link is cancelled or
// disconnected. Releases the lock while the request callback runs. For a
// characteristic read, `value` is where the value goes and `*value_size`
// gets its size.
static dc_status_t
live_request (al_link_t *link, int32_t kind, const unsigned char *data, size_t size, const char *uuid, unsigned char *value, size_t value_capacity, size_t *value_size)
{
	dc_status_t status = request_gate (link);
	if (status != DC_STATUS_SUCCESS)
		return status;

	link->req_data.size = 0;
	if (!buffer_reserve (&link->req_data, size))
		return DC_STATUS_NOMEMORY;
	buffer_put (&link->req_data, data, size);

	uint64_t seq = ++link->next_seq;
	link->req_seq = seq;
	link->req_kind = kind;
	link->req_done = 0;
	link->req_status = DC_STATUS_SUCCESS;
	if (uuid != NULL)
		memcpy (link->req_uuid, uuid, DC_BLE_UUID_SIZE);
	else
		link->req_uuid[0] = '\0';
	link->req_value = value;
	link->req_value_capacity = value_capacity;
	link->req_value_size = 0;

	int timeout = link->write_timeout;
	uint64_t deadline = 0;
	if (timeout > 0)
		deadline = al_monotonic_us () + (uint64_t) timeout * 1000u;
	al_request_fn request = link->request;

	// The request may be taken, and even completed, before the callback
	// runs: the wait below checks first.
	al_mutex_unlock (&link->lock);
	request ((intptr_t) link, kind);
	al_mutex_lock (&link->lock);

	for (;;) {
		if (link->req_seq == seq && link->req_done)
			break;
		if (link->cancelled || link->disconnected || link->closed)
			break;
		if (timeout < 0) {
			al_cond_wait (&link->cond, &link->lock);
		} else {
			uint64_t now = al_monotonic_us ();
			if (now >= deadline)
				break;
			al_cond_timedwait (&link->cond, &link->lock, deadline - now);
		}
	}

	if (link->req_seq == seq && link->req_done) {
		// Completed, even if a cancel or a disconnect came after.
		status = link->req_status;
		if (value_size != NULL)
			*value_size = link->req_value_size;
	} else if (link->cancelled) {
		status = DC_STATUS_CANCELLED;
	} else if (link->disconnected || link->closed) {
		status = DC_STATUS_IO;
	} else {
		status = DC_STATUS_TIMEOUT;
	}

	// Empty the slot. From here on a completion for this request finds
	// nothing taken, and al_link_complete no longer writes to `value`.
	link->req_seq = 0;
	link->req_kind = 0;
	link->req_done = 0;
	link->req_value = NULL;
	link->req_value_capacity = 0;
	link->req_value_size = 0;

	return status;
}

// ---------------------------------------------------------------------------
// The replay link. All of these run with the lock held.

static dc_status_t
replay_gate (al_link_t *link)
{
	if (link->cancelled)
		return DC_STATUS_CANCELLED;
	if (link->disconnected || link->closed)
		return DC_STATUS_IO;
	return DC_STATUS_SUCCESS;
}

// Skips to the next R, W or C. Returns 0 at the end of the recording. The
// layout was checked when the link was made.
static int
replay_next (al_link_t *link, event_t *event)
{
	while (link->rp_offset < link->events_size) {
		const unsigned char *p = link->events + link->rp_offset;
		size_t length = get_u32 (p + 9);
		if (p[0] == 'R' || p[0] == 'W' || p[0] == 'C') {
			event->kind = p[0];
			event->payload = p + EVENT_HEADER;
			event->size = length;
			return 1;
		}
		link->rp_offset += EVENT_HEADER + length;
		link->rp_index++;
		link->rp_consumed = 0;
	}
	return 0;
}

// Moves past the event replay_next returned.
static void
replay_advance (al_link_t *link, const event_t *event)
{
	link->rp_offset += EVENT_HEADER + event->size;
	link->rp_index++;
	link->rp_consumed = 0;
}

// After replay_advance past a W, a C or an R of length 0: what that call
// returned live. An E that follows it, past events a replay skips (an X
// overflow can land between the two), gives the status, and is consumed;
// without one the call returned `otherwise`. Recordings made before E
// existed have none, so their writes succeed and their empty reads time out.
static dc_status_t
replay_result (al_link_t *link, dc_status_t otherwise)
{
	size_t offset = link->rp_offset;
	int index = link->rp_index;
	while (offset < link->events_size) {
		const unsigned char *p = link->events + offset;
		size_t length = get_u32 (p + 9);
		if (p[0] == 'E') {
			// A malformed E (not 4 bytes) still counts as a failure.
			dc_status_t status = length == 4 ?
				(dc_status_t) (int32_t) get_u32 (p + EVENT_HEADER) : DC_STATUS_IO;
			link->rp_offset = offset + EVENT_HEADER + length;
			link->rp_index = index + 1;
			return status == DC_STATUS_SUCCESS ? otherwise : status;
		}
		if (p[0] == 'R' || p[0] == 'W' || p[0] == 'C')
			break;
		offset += EVENT_HEADER + length;
		index++;
	}
	return otherwise;
}

// Whether `events` holds whole events, well-formed C payloads, and few
// enough events for an int index.
static int
replay_valid (const unsigned char *events, size_t size)
{
	size_t offset = 0;
	int n = 0;
	while (offset < size) {
		if (size - offset < EVENT_HEADER)
			return 0;
		const unsigned char *p = events + offset;
		size_t length = get_u32 (p + 9);
		if (length > size - offset - EVENT_HEADER)
			return 0;
		if (p[0] == 'C') {
			if (length < 2 || p[EVENT_HEADER + 1] > length - 2)
				return 0;
		}
		if (n == 0x7FFFFFFF)
			return 0;
		offset += EVENT_HEADER + length;
		n++;
	}
	return 1;
}

// ---------------------------------------------------------------------------
// The custom iostream's callbacks. libdivecomputer calls them from one
// thread; dc_iostream_read and the others always pass `actual` and `value`.

static void
log_divergence (dc_context_t *context, const char *what, int index)
{
	if (index < 0)
		return;
	ERROR (context, "Replay: the %s does not match the recording at event %d.", what, index);
}

static dc_status_t
link_set_timeout (void *userdata, int timeout)
{
	al_link_t *link = (al_link_t *) userdata;
	al_mutex_lock (&link->lock);
	link->timeout = timeout;
	record_u32 (link, 'T', (uint32_t) timeout);
	al_mutex_unlock (&link->lock);
	return DC_STATUS_SUCCESS;
}

static dc_status_t
link_line (void *userdata, const char *name, unsigned int value)
{
	al_link_t *link = (al_link_t *) userdata;
	char text[32];
	dc_platform_snprintf (text, sizeof (text), "%s %u", name, value);
	al_mutex_lock (&link->lock);
	record_text (link, text);
	al_mutex_unlock (&link->lock);
	return DC_STATUS_SUCCESS;
}

static dc_status_t
link_set_break (void *userdata, unsigned int value)
{
	return link_line (userdata, "set_break", value);
}

static dc_status_t
link_set_dtr (void *userdata, unsigned int value)
{
	return link_line (userdata, "set_dtr", value);
}

static dc_status_t
link_set_rts (void *userdata, unsigned int value)
{
	return link_line (userdata, "set_rts", value);
}

static dc_status_t
link_get_lines (void *userdata, unsigned int *value)
{
	(void) userdata;
	(void) value;
	return DC_STATUS_UNSUPPORTED;
}

static dc_status_t
link_get_available (void *userdata, size_t *value)
{
	al_link_t *link = (al_link_t *) userdata;
	al_mutex_lock (&link->lock);
	if (link->replay) {
		event_t event;
		*value = 0;
		if (replay_next (link, &event) && event.kind == 'R')
			*value = event.size - link->rp_consumed;
	} else {
		*value = link->queued;
	}
	al_mutex_unlock (&link->lock);
	return DC_STATUS_SUCCESS;
}

static dc_status_t
link_configure (void *userdata, unsigned int baudrate, unsigned int databits, dc_parity_t parity, dc_stopbits_t stopbits, dc_flowcontrol_t flowcontrol)
{
	al_link_t *link = (al_link_t *) userdata;
	static const char parities[] = "NOEMS";
	char p = (unsigned int) parity < sizeof (parities) - 1 ? parities[parity] : '?';
	const char *s = stopbits == DC_STOPBITS_ONE ? "1" :
		stopbits == DC_STOPBITS_ONEPOINTFIVE ? "1.5" :
		stopbits == DC_STOPBITS_TWO ? "2" : "?";
	const char *f = flowcontrol == DC_FLOWCONTROL_NONE ? "" :
		flowcontrol == DC_FLOWCONTROL_HARDWARE ? " rtscts" :
		flowcontrol == DC_FLOWCONTROL_SOFTWARE ? " xonxoff" : " ?";
	char text[64];
	dc_platform_snprintf (text, sizeof (text), "configure %u %u%c%s%s", baudrate, databits, p, s, f);
	al_mutex_lock (&link->lock);
	record_text (link, text);
	al_mutex_unlock (&link->lock);
	return DC_STATUS_SUCCESS;
}

static dc_status_t
link_poll (void *userdata, int timeout)
{
	al_link_t *link = (al_link_t *) userdata;
	dc_status_t status;
	al_mutex_lock (&link->lock);
	if (link->replay) {
		event_t event;
		status = replay_gate (link);
		// An R of length 0 is a read that timed out: nothing to poll.
		if (status == DC_STATUS_SUCCESS)
			status = replay_next (link, &event) && event.kind == 'R' &&
				event.size > link->rp_consumed ?
				DC_STATUS_SUCCESS : DC_STATUS_TIMEOUT;
	} else {
		status = wait_for_packet (link, timeout);
	}
	al_mutex_unlock (&link->lock);
	return status;
}

static dc_status_t
link_read (void *userdata, void *data, size_t size, size_t *actual)
{
	al_link_t *link = (al_link_t *) userdata;
	unsigned char *out = (unsigned char *) data;
	dc_status_t status;
	size_t n = 0;
	int diverged = -1;

	*actual = 0;
	if (size == 0)
		return DC_STATUS_SUCCESS;

	al_mutex_lock (&link->lock);
	dc_context_t *context = link->context;
	if (link->replay) {
		event_t event;
		status = replay_gate (link);
		if (status != DC_STATUS_SUCCESS) {
			// Cancelled or disconnected.
		} else if (!replay_next (link, &event)) {
			// The recording ends: the computer has nothing more to say.
			status = DC_STATUS_TIMEOUT;
		} else if (event.kind != 'R') {
			diverged = link->rp_index;
			status = DC_STATUS_PROTOCOL;
		} else if (event.size == 0) {
			// A read that returned nothing live: what it returned, by
			// default a timeout.
			replay_advance (link, &event);
			status = replay_result (link, DC_STATUS_TIMEOUT);
		} else {
			n = event.size - link->rp_consumed;
			if (n > size)
				n = size;
			memcpy (out, event.payload + link->rp_consumed, n);
			link->rp_consumed += n;
			if (link->rp_consumed == event.size)
				replay_advance (link, &event);
		}
	} else {
		status = wait_for_packet (link, link->timeout);
		if (status == DC_STATUS_SUCCESS) {
			packet_t *packet = link->head;
			n = packet->size - packet->offset;
			if (n > size)
				n = size;
			memcpy (out, packet->data + packet->offset, n);
			packet->offset += n;
			link->queued -= n;
			if (packet->offset == packet->size) {
				link->head = packet->next;
				if (link->head == NULL)
					link->tail = NULL;
				free (packet);
			}
		}
	}
	if (status == DC_STATUS_SUCCESS) {
		*actual = n;
		record (link, 'R', out, n, NULL, 0);
	} else {
		record_failed_read (link, status);
	}
	al_mutex_unlock (&link->lock);

	log_divergence (context, "read", diverged);
	return status;
}

static dc_status_t
link_write (void *userdata, const void *data, size_t size, size_t *actual)
{
	al_link_t *link = (al_link_t *) userdata;
	const unsigned char *bytes = (const unsigned char *) data;
	dc_status_t status;
	int diverged = -1;

	*actual = 0;

	al_mutex_lock (&link->lock);
	dc_context_t *context = link->context;
	status = link->replay ? replay_gate (link) : request_gate (link);
	if (size == 0) {
		// A write of nothing has nothing to send: no request, no event.
	} else if (link->replay) {
		event_t event;
		if (status != DC_STATUS_SUCCESS) {
			// Cancelled or disconnected.
		} else if (!replay_next (link, &event) || event.kind != 'W' ||
			event.size != size || memcmp (event.payload, bytes, size) != 0) {
			// Stay at this event: a retry with the right bytes matches.
			diverged = link->rp_index;
			status = DC_STATUS_PROTOCOL;
		} else {
			replay_advance (link, &event);
			status = replay_result (link, DC_STATUS_SUCCESS);
		}
		record (link, 'W', bytes, size, NULL, 0);
		record_result (link, status);
	} else {
		// W when the write is issued, so that it shows even if it fails;
		// E with the result when it did.
		record (link, 'W', bytes, size, NULL, 0);
		if (status == DC_STATUS_SUCCESS)
			status = live_request (link, AL_REQ_WRITE, bytes, size, NULL, NULL, 0, NULL);
		record_result (link, status);
	}
	if (status == DC_STATUS_SUCCESS)
		*actual = size;
	al_mutex_unlock (&link->lock);

	log_divergence (context, "write", diverged);
	return status;
}

// Copies the advertised name, truncated to `size` and always NUL-terminated,
// like strncpy plus a terminator. oceanic_atom2.c passes a fixed 9-byte
// buffer and forces the NUL itself.
static dc_status_t
link_get_name (al_link_t *link, void *data, size_t size)
{
	if (link->name == NULL)
		return DC_STATUS_UNSUPPORTED;
	if (data == NULL || size == 0)
		return DC_STATUS_INVALIDARGS;
	size_t n = strlen (link->name);
	if (n > size - 1)
		n = size - 1;
	memcpy (data, link->name, n);
	((char *) data)[n] = '\0';
	return DC_STATUS_SUCCESS;
}

// DC_IOCTL_BLE_CHARACTERISTIC_READ and _WRITE: a dc_ble_uuid_t, then the
// value (read: room for it).
static dc_status_t
link_characteristic (al_link_t *link, int read, void *data, size_t size)
{
	unsigned char *bytes = (unsigned char *) data;
	char uuid[DC_BLE_UUID_SIZE];
	dc_status_t status;
	int diverged = -1;
	const char *what = "characteristic request";

	if (bytes == NULL || size < sizeof (dc_ble_uuid_t))
		return DC_STATUS_INVALIDARGS;
	if (dc_ble_uuid2str (bytes, uuid, sizeof (uuid)) == NULL)
		return DC_STATUS_INVALIDARGS;
	unsigned char *value = bytes + sizeof (dc_ble_uuid_t);
	size_t value_size = size - sizeof (dc_ble_uuid_t);
	unsigned int direction = read ? DC_IOCTL_DIR_READ : DC_IOCTL_DIR_WRITE;
	// What a characteristic read put in `value`.
	size_t got = 0;

	al_mutex_lock (&link->lock);
	dc_context_t *context = link->context;
	if (link->replay) {
		event_t event;
		status = replay_gate (link);
		if (status != DC_STATUS_SUCCESS) {
			// Cancelled or disconnected.
		} else if (!replay_next (link, &event) || event.kind != 'C' ||
			event.payload[0] != direction ||
			event.payload[1] != UUID_LENGTH ||
			!ascii_equal_ignoring_case (event.payload + 2, uuid, UUID_LENGTH)) {
			diverged = link->rp_index;
			status = DC_STATUS_PROTOCOL;
		} else {
			const unsigned char *recorded = event.payload + 2 + UUID_LENGTH;
			size_t recorded_size = event.size - 2 - UUID_LENGTH;
			if (read && recorded_size > value_size) {
				// Stay at this event, as for any divergence.
				diverged = link->rp_index;
				what = "characteristic read, longer than the buffer,";
				status = DC_STATUS_INVALIDARGS;
			} else if (!read && (recorded_size != value_size ||
				memcmp (recorded, value, value_size) != 0)) {
				diverged = link->rp_index;
				status = DC_STATUS_PROTOCOL;
			} else {
				if (read) {
					memcpy (value, recorded, recorded_size);
					got = recorded_size;
				}
				replay_advance (link, &event);
				status = replay_result (link, DC_STATUS_SUCCESS);
			}
		}
	} else if (read) {
		status = live_request (link, AL_REQ_CHAR_READ, NULL, 0, uuid, value, value_size, &got);
	} else {
		// C when the write is issued, so that it shows even if it fails.
		record_characteristic (link, direction, uuid, value, value_size);
		status = request_gate (link);
		if (status == DC_STATUS_SUCCESS)
			status = live_request (link, AL_REQ_CHAR_WRITE, value, value_size, uuid, NULL, 0, NULL);
	}
	if (read || link->replay) {
		// A read is recorded with what it returned: nothing when it failed.
		if (read && status != DC_STATUS_SUCCESS)
			got = 0;
		record_characteristic (link, direction, uuid, value, read ? got : value_size);
	}
	record_result (link, status);
	al_mutex_unlock (&link->lock);

	log_divergence (context, what, diverged);
	return status;
}

static dc_status_t
link_ioctl (void *userdata, unsigned int request, void *data, size_t size)
{
	al_link_t *link = (al_link_t *) userdata;

	switch (request) {
	case DC_IOCTL_BLE_GET_NAME:
		return link_get_name (link, data, size);
	case DC_IOCTL_BLE_CHARACTERISTIC_READ:
		return link_characteristic (link, 1, data, size);
	case DC_IOCTL_BLE_CHARACTERISTIC_WRITE:
		return link_characteristic (link, 0, data, size);
	default:
		// PIN code and access codes wait for a PIN prompt in the app.
		al_mutex_lock (&link->lock);
		record_u32 (link, 'I', request);
		al_mutex_unlock (&link->lock);
		return DC_STATUS_UNSUPPORTED;
	}
}

static dc_status_t
link_flush (void *userdata)
{
	// Every write was complete before it returned.
	(void) userdata;
	return DC_STATUS_SUCCESS;
}

static dc_status_t
link_purge (void *userdata, dc_direction_t direction)
{
	al_link_t *link = (al_link_t *) userdata;
	// Output: nothing is buffered. A replay holds only what was read, so
	// there is nothing to drop either.
	if (link->replay || !(direction & DC_DIRECTION_INPUT))
		return DC_STATUS_SUCCESS;
	al_mutex_lock (&link->lock);
	size_t dropped = link->queued;
	queue_clear (link);
	record_u32 (link, 'P', (uint32_t) dropped);
	al_mutex_unlock (&link->lock);
	return DC_STATUS_SUCCESS;
}

static dc_status_t
link_sleep (void *userdata, unsigned int milliseconds)
{
	al_link_t *link = (al_link_t *) userdata;

	al_mutex_lock (&link->lock);
	int cancelled = link->cancelled;
	if (!cancelled)
		record_u32 (link, 'S', milliseconds);
	al_mutex_unlock (&link->lock);
	if (cancelled)
		return DC_STATUS_CANCELLED;
	if (link->replay)
		return DC_STATUS_SUCCESS;

	// Plain sleeps of at most 50 ms, checking for a cancel after each.
	uint64_t deadline = al_monotonic_us () + (uint64_t) milliseconds * 1000u;
	for (;;) {
		uint64_t now = al_monotonic_us ();
		if (now >= deadline)
			return DC_STATUS_SUCCESS;
		uint64_t left = (deadline - now + 999) / 1000;
		al_sleep_ms (left < 50 ? (unsigned int) left : 50);
		al_mutex_lock (&link->lock);
		cancelled = link->cancelled;
		al_mutex_unlock (&link->lock);
		if (cancelled)
			return DC_STATUS_CANCELLED;
	}
}

static dc_status_t
link_close (void *userdata)
{
	al_link_t *link = (al_link_t *) userdata;
	al_mutex_lock (&link->lock);
	link->closed = 1;
	queue_clear (link);
	al_cond_broadcast (&link->cond);
	al_mutex_unlock (&link->lock);
	return DC_STATUS_SUCCESS;
}

static const dc_custom_cbs_t link_callbacks = {
	link_set_timeout,
	link_set_break,
	link_set_dtr,
	link_set_rts,
	link_get_lines,
	link_get_available,
	link_configure,
	link_poll,
	link_read,
	link_write,
	link_ioctl,
	link_flush,
	link_purge,
	link_sleep,
	link_close,
};

// ---------------------------------------------------------------------------
// The API

static al_link_t *
link_new (const char *advertised_name, al_request_fn request, int replay)
{
	al_link_t *link = (al_link_t *) calloc (1, sizeof (al_link_t));
	if (link == NULL)
		return NULL;

	if (advertised_name != NULL) {
		size_t n = strlen (advertised_name) + 1;
		link->name = (char *) malloc (n);
		if (link->name == NULL) {
			free (link);
			return NULL;
		}
		memcpy (link->name, advertised_name, n);
	}
	if (al_mutex_init (&link->lock) != 0) {
		free (link->name);
		free (link);
		return NULL;
	}
	if (al_cond_init (&link->cond) != 0) {
		al_mutex_destroy (&link->lock);
		free (link->name);
		free (link);
		return NULL;
	}

	link->replay = replay;
	link->request = request;
	link->origin = al_monotonic_us ();
	// libdivecomputer's default for an iostream: a read waits for data.
	link->timeout = -1;
	link->write_timeout = AL_LINK_WRITE_TIMEOUT;
	return link;
}

al_link_t *
al_link_new_live (const char *advertised_name, al_request_fn request)
{
	if (request == NULL)
		return NULL;
	return link_new (advertised_name, request, 0);
}

al_link_t *
al_link_new_replay (const char *advertised_name, const uint8_t *events, size_t size)
{
	if (events == NULL && size > 0)
		return NULL;
	if (size > 0 && !replay_valid (events, size))
		return NULL;

	al_link_t *link = link_new (advertised_name, NULL, 1);
	if (link == NULL)
		return NULL;
	if (size > 0) {
		link->events = (unsigned char *) malloc (size);
		if (link->events == NULL) {
			al_link_free (link);
			return NULL;
		}
		memcpy (link->events, events, size);
		link->events_size = size;
	}
	return link;
}

void
al_link_free (al_link_t *link)
{
	if (link == NULL)
		return;
	queue_clear (link);
	free (link->req_data.data);
	free (link->rec.data);
	free (link->events);
	free (link->name);
	al_cond_destroy (&link->cond);
	al_mutex_destroy (&link->lock);
	free (link);
}

dc_status_t
al_link_iostream (al_link_t *link, dc_context_t *context, dc_iostream_t **out)
{
	if (link == NULL || out == NULL)
		return DC_STATUS_INVALIDARGS;
	al_mutex_lock (&link->lock);
	link->context = context;
	link->closed = 0;
	al_mutex_unlock (&link->lock);
	return dc_custom_open (out, context, DC_TRANSPORT_BLE, &link_callbacks, link);
}

void
al_link_push (al_link_t *link, const uint8_t *data, size_t size)
{
	if (link == NULL || link->replay || data == NULL || size == 0)
		return;

	// Copy outside the lock; a packet can be large.
	packet_t *packet = NULL;
	if (size <= (size_t) AL_LINK_QUEUE_LIMIT) {
		packet = (packet_t *) malloc (sizeof (packet_t) + size);
		if (packet != NULL) {
			packet->next = NULL;
			packet->size = size;
			packet->offset = 0;
			packet->data = (unsigned char *) (packet + 1);
			memcpy (packet->data, data, size);
		}
	}

	al_mutex_lock (&link->lock);
	if (link->disconnected || link->closed || link->overflowed) {
		free (packet);
	} else if (packet == NULL || size > (size_t) AL_LINK_QUEUE_LIMIT - link->queued) {
		// Too much, or no memory for it: what is queued no longer adds up
		// to the computer's stream, so every later read fails.
		free (packet);
		link->overflowed = 1;
		queue_clear (link);
		record_text (link, "overflow");
	} else {
		if (link->tail != NULL)
			link->tail->next = packet;
		else
			link->head = packet;
		link->tail = packet;
		link->queued += size;
	}
	al_cond_broadcast (&link->cond);
	al_mutex_unlock (&link->lock);
}

size_t
al_link_pending (al_link_t *link, uint8_t *data, size_t capacity, char *uuid, size_t uuid_capacity, int64_t *request_id, int32_t *kind)
{
	size_t size = 0;

	if (uuid != NULL && uuid_capacity > 0)
		uuid[0] = '\0';
	if (request_id != NULL)
		*request_id = 0;
	if (kind != NULL)
		*kind = 0;
	// Without somewhere to put the id, nothing could complete the request.
	if (link == NULL || request_id == NULL)
		return 0;

	al_mutex_lock (&link->lock);
	if (link->req_seq != 0 && link->taken_seq != link->req_seq && !link->req_done) {
		int characteristic = link->req_kind != AL_REQ_WRITE;
		size_t needed = link->req_data.size;
		if (kind != NULL)
			*kind = link->req_kind;
		if (needed > capacity || (needed > 0 && data == NULL) ||
			(characteristic && (uuid == NULL || uuid_capacity < DC_BLE_UUID_SIZE))) {
			// Not taken: the caller asks again with room for `needed`
			// bytes and a whole UUID.
			*request_id = -1;
			size = needed;
		} else {
			if (needed > 0)
				memcpy (data, link->req_data.data, needed);
			if (characteristic)
				memcpy (uuid, link->req_uuid, DC_BLE_UUID_SIZE);
			link->taken_seq = link->req_seq;
			*request_id = (int64_t) link->req_seq;
			size = needed;
		}
	}
	al_mutex_unlock (&link->lock);
	return size;
}

void
al_link_complete (al_link_t *link, int64_t request_id, dc_status_t status, const uint8_t *data, size_t size)
{
	if (link == NULL || request_id <= 0)
		return;
	al_mutex_lock (&link->lock);
	// Only the request in the slot, by its id: a completion for one that
	// timed out, a duplicate, or one from an interleaved handler that
	// finished out of order does nothing.
	if (link->req_seq == (uint64_t) request_id &&
		link->taken_seq == link->req_seq && !link->req_done) {
		if (status == DC_STATUS_SUCCESS && link->req_kind == AL_REQ_CHAR_READ) {
			// The blocking thread waits in the slot until it is emptied,
			// so its ioctl buffer, `req_value`, is still there.
			if (size > link->req_value_capacity || (size > 0 && data == NULL)) {
				status = DC_STATUS_INVALIDARGS;
			} else {
				if (size > 0)
					memcpy (link->req_value, data, size);
				link->req_value_size = size;
			}
		}
		link->req_status = status;
		link->req_done = 1;
		al_cond_broadcast (&link->cond);
	}
	al_mutex_unlock (&link->lock);
}

void
al_link_disconnected (al_link_t *link)
{
	if (link == NULL)
		return;
	al_mutex_lock (&link->lock);
	link->disconnected = 1;
	al_cond_broadcast (&link->cond);
	al_mutex_unlock (&link->lock);
}

void
al_link_cancel (al_link_t *link)
{
	if (link == NULL)
		return;
	al_mutex_lock (&link->lock);
	link->cancelled = 1;
	al_cond_broadcast (&link->cond);
	al_mutex_unlock (&link->lock);
}

int
al_link_cancelled (void *userdata)
{
	al_link_t *link = (al_link_t *) userdata;
	if (link == NULL)
		return 0;
	al_mutex_lock (&link->lock);
	int cancelled = link->cancelled;
	al_mutex_unlock (&link->lock);
	return cancelled;
}

void
al_link_set_write_timeout (al_link_t *link, int milliseconds)
{
	if (link == NULL)
		return;
	al_mutex_lock (&link->lock);
	link->write_timeout = milliseconds;
	al_mutex_unlock (&link->lock);
}

void
al_link_set_recording (al_link_t *link, int enabled)
{
	if (link == NULL)
		return;
	al_mutex_lock (&link->lock);
	link->recording = enabled != 0;
	al_mutex_unlock (&link->lock);
}

size_t
al_link_recording (al_link_t *link, uint8_t *data, size_t capacity)
{
	if (link == NULL)
		return 0;
	al_mutex_lock (&link->lock);
	size_t size = link->rec.size;
	if (size > 0 && size <= capacity && data != NULL)
		memcpy (data, link->rec.data, size);
	al_mutex_unlock (&link->lock);
	return size;
}

int
al_link_replay_position (al_link_t *link)
{
	if (link == NULL || !link->replay)
		return -1;
	al_mutex_lock (&link->lock);
	int position = link->rp_index;
	al_mutex_unlock (&link->lock);
	return position;
}
