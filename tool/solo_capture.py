#!/usr/bin/env python3
"""Capture the Divesoft SOLO's USB output with arrival times (issue #113).

Throwaway tool for the background-logging design: find out what the SOLO
sends when OK is pressed (suspend / resume). Standard library only.

Usage:
    python3 solo_capture.py [/dev/cu.usbmodemXXXX] [out.log]

While it runs, press Enter in this terminal at the moment you press a key on
the SOLO, and type what you did first if you like ("ok", "ok resume",
"mode", "power off"), then Enter. Ctrl-C stops.

Every output line is:
    <seconds since start> <wall clock> RX <hex-escaped line>   (data)
    <seconds since start> <wall clock> GAP <seconds>           (silence > 0.5 s)
    <seconds since start> <wall clock> MARK <your text>        (your Enter)
"""
import glob
import os
import select
import sys
import termios
import time
import tty


def find_port():
    print("Waiting for the SOLO (/dev/cu.usbmodem*) ... plug it in and switch it on.")
    for _ in range(600):  # up to 5 minutes
        ports = sorted(glob.glob("/dev/cu.usbmodem*"))
        if ports:
            time.sleep(1.0)  # let it finish enumerating
            return ports[0]
        time.sleep(0.5)
    sys.exit("No /dev/cu.usbmodem* found. Is the SOLO plugged in and on?")


def open_port(path):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    tty.setraw(fd)
    attrs = termios.tcgetattr(fd)
    attrs[4] = attrs[5] = termios.B115200  # ispeed, ospeed
    attrs[2] |= termios.CLOCAL | termios.CREAD
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    # Opening a tty on macOS raises DTR; the SOLO needs it to send.
    return fd


def escape(raw):
    out = []
    for b in raw:
        if 32 <= b < 127 and b != 0x5C:
            out.append(chr(b))
        else:
            out.append("\\x%02x" % b)
    return "".join(out)


def main():
    port = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else find_port()
    out_path = sys.argv[2] if len(sys.argv) > 2 else time.strftime(
        "solo_capture_%Y%m%d_%H%M%S.log")
    fd = open_port(port)
    t0 = time.monotonic()
    last_rx = None
    buf = b""
    print(f"Reading {port}, writing {out_path}. Enter = mark, Ctrl-C = stop.")
    with open(out_path, "w") as log:
        def emit(kind, text):
            now = time.monotonic() - t0
            stamp = time.strftime("%H:%M:%S") + ".%03d" % (
                int(time.time() * 1000) % 1000)
            line = f"{now:9.3f} {stamp} {kind} {text}"
            log.write(line + "\n")
            log.flush()
            print(line)

        try:
            while True:
                ready, _, _ = select.select([fd, sys.stdin], [], [], 0.1)
                if sys.stdin in ready:
                    emit("MARK", sys.stdin.readline().strip() or "(enter)")
                if fd in ready:
                    try:
                        chunk = os.read(fd, 4096)
                    except BlockingIOError:
                        chunk = b""
                    except OSError as e:  # unplugged / powered off
                        emit("ERROR", repr(e))
                        break
                    if not chunk:
                        emit("EOF", "port closed")
                        break
                    now = time.monotonic()
                    if last_rx is not None and now - last_rx > 0.5:
                        emit("GAP", f"{now - last_rx:.3f}")
                    last_rx = now
                    buf += chunk
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        emit("RX", escape(line + b"\n"))
        except KeyboardInterrupt:
            if buf:
                emit("RX-PARTIAL", escape(buf))
            emit("STOP", "ctrl-c")
    os.close(fd)


if __name__ == "__main__":
    main()
