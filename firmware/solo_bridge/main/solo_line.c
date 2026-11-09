// SPDX-License-Identifier: Apache-2.0
#include "solo_line.h"

#include <ctype.h>
#include <stddef.h>

static bool is_space(char c) { return isspace((unsigned char)c) != 0; }

static bool is_value_char(char c) {
    return isdigit((unsigned char)c) || c == '.' || c == '-' || c == '*';
}

bool solo_is_data_line(const char *line) {
    const char *p = line;
    while (*p) {
        while (*p && is_space(*p)) p++;
        const char *tok = p;
        while (*p && !is_space(*p)) p++;
        size_t len = (size_t)(p - tok);
        if (len == 2 && (tok[0] == 'O' || tok[0] == 'o') && tok[1] == '2') {
            const char *v = p;
            while (*v && is_space(*v)) v++;
            const char *vend = v;
            while (*vend && !is_space(*vend)) vend++;
            bool ok = vend > v;
            for (const char *c = v; ok && c < vend; c++) ok = is_value_char(*c);
            if (ok) return true;
            // Like the app's parser, a later "O2" token may still carry it.
        }
    }
    return false;
}
