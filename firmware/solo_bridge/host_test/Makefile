# SPDX-License-Identifier: Apache-2.0
#
# Builds and runs the host tests of the pure firmware modules:
#   make -C firmware/solo_bridge/host_test

CC ?= cc
CFLAGS = -std=c11 -Wall -Wextra -Werror -O1 -g -I../main -I.

# Pure modules from ../main, and their tests.
SRCS = power_logic.c line_splitter.c solo_line.c bridge_proto.c hold_detector.c
TESTS = test_main.c test_power_logic.c test_line_splitter.c test_bridge_proto.c \
        test_hold_detector.c capture_reader.c

all: test_main
	cd $(CURDIR) && ./test_main

test_main: $(TESTS) $(addprefix ../main/,$(SRCS)) check.h $(wildcard ../main/*.h) $(wildcard *.h)
	$(CC) $(CFLAGS) -o $@ $(TESTS) $(addprefix ../main/,$(SRCS))

clean:
	rm -f test_main golden/*.out

.PHONY: all clean
