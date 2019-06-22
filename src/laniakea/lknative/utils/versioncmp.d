/*
 * Copyright (C) 2016 Matthias Klumpp <matthias@tenstral.net>
 * Copyright (C) The APT development team.
 *
 * Licensed under the GNU Lesser General Public License Version 3
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the license, or
 * (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this software.  If not, see <http://www.gnu.org/licenses/>.
 */

module lknative.utils.versioncmp;
@safe:

import std.ascii;
import std.conv : to;
import std.string : indexOf, lastIndexOf, toStringz;
import std.stdio;

/**
 * This compares a fragment of the version. This is a slightly adapted
 * version of what dpkg uses in dpkg/lib/dpkg/version.c.
 * In particular, the a | b = NULL check is removed as we check this in the
 * caller, we use an explicit end for a | b strings and we check ~ explicit.
 */
private int order (char c) pure
{
    if (c.isDigit)
        return 0;
    else if (c.isAlpha)
        return c;
    else if (c == '~')
        return -1;
    else if (c)
        return c + 256;
    else
        return 0;
}

/**
 * Iterate over the whole string
 * What this does is to split the whole string into groups of
 * numeric and non numeric portions. For instance:
 *    a67bhgs89
 * Has 4 portions 'a', '67', 'bhgs', '89'. A more normal:
 *    2.7.2-linux-1
 * Has '2', '.', '7', '.' ,'-linux-','1'
 */
private int cmpFragment (const(immutable(char)*) a, const(immutable(char)*) aEnd,
                         const(immutable(char)*) b, const(immutable(char)*) bEnd) @trusted pure
{
    immutable(char) *lhs = a;
    immutable(char) *rhs = b;

    while (lhs != aEnd && rhs != bEnd) {
        int first_diff = 0;

        while (lhs != aEnd && rhs != bEnd && (!(*lhs).isDigit || !(*rhs).isDigit)) {
            int vc = order (*lhs);
            int rc = order (*rhs);

            if (vc != rc)
                return vc - rc;
            ++lhs; ++rhs;
        }

        while (*lhs == '0')
            ++lhs;
        while (*rhs == '0')
            ++rhs;
        while ((*lhs).isDigit && (*rhs).isDigit) {
            if (!first_diff)
                first_diff = *lhs - *rhs;
            ++lhs;
            ++rhs;
        }

        if ((*lhs).isDigit)
            return 1;
        if ((*rhs).isDigit)
            return -1;
        if (first_diff)
            return first_diff;
    }

    // The strings must be equal
    if (lhs == aEnd && rhs == bEnd)
        return 0;

    // lhs is shorter
    if (lhs == aEnd) {
        if (*rhs == '~')
            return 1;
        return -1;
    }

    // rhs is shorter
    if (rhs == bEnd) {
        if (*lhs == '~')
            return -1;
        return 1;
    }

    // Shouldn't happen
    return 1;
}

// import from string.h, needs glibc
private extern(C) void *memrchr (const void *s, int c, size_t n) @system pure;

/**
 * Compare two Debian-style version numbers.
 */
export int compareVersions (const string a, const string b) @trusted pure
{
    import core.stdc.string;

    immutable(char) *ac = a.toStringz;
    immutable(char) *bc = b.toStringz;

    immutable(char*) aEnd = ac + a.length;
    immutable(char*) bEnd = bc + b.length;

    // Strip off the epoch and compare it
    auto lhs = cast(immutable(char)*) memchr (ac, ':', aEnd - ac);
    auto rhs = cast(immutable(char)*) memchr (bc, ':', bEnd - bc);

    if (lhs is null)
        lhs = ac;
    if (rhs is null)
        rhs = bc;

    // Special case: a zero epoch is the same as no epoch,
    // so remove it.
    if (lhs != ac) {
        for (; *ac == '0'; ++ac) {}
        if (ac == lhs) {
            ++ac;
            ++lhs;
        }
    }
    if (rhs != bc) {
        for (; *bc == '0'; ++bc) {}
        if (bc == rhs) {
            ++bc;
            ++rhs;
        }
    }

    // Compare the epoch
    auto res = cmpFragment (ac, lhs, bc, rhs);
    if (res != 0)
        return res;

    // Skip the :
    if (lhs != ac)
        lhs++;
    if (rhs != bc)
        rhs++;

    // Find the last -
    auto dlhs = cast(immutable(char)*) memrchr (lhs, '-', aEnd - lhs);
    auto drhs = cast(immutable(char)*) memrchr (rhs, '-', bEnd - rhs);
    if (dlhs is null)
        dlhs = aEnd;
    if (drhs is null)
        drhs = bEnd;

    // Compare the main version
    res = cmpFragment (lhs, dlhs, rhs, drhs);
    if (res != 0)
        return res;

    // Skip the -
    if (dlhs != lhs)
        dlhs++;
    if (drhs != rhs)
        drhs++;

    // no debian revision need to be treated like -0
    if (*(dlhs - 1) == '-' && *(drhs - 1) == '-') {
        return cmpFragment (dlhs, aEnd, drhs, bEnd);
    } else if (*(dlhs - 1) == '-') {
        immutable(char)* zeroZ = "0";
        return cmpFragment (dlhs, aEnd, zeroZ, zeroZ + 1);
    } else if (*(drhs - 1) == '-') {
        immutable(char)* zeroZ = "0";
        return cmpFragment (zeroZ, zeroZ + 1, drhs, bEnd);
    } else {
        return 0;
    }
}

unittest
{
    assert (compareVersions ("6", "8") < 0);
    assert (compareVersions ("0.6.12b-d", "0.6.12a") > 0);
    assert (compareVersions ("7.4", "7.4") == 0);
    assert (compareVersions ("ab.d", "ab.f") < 0);

    assert (compareVersions ("0.6.16", "0.6.14") > 0);

    assert (compareVersions ("3.0.rc2", "3.0.0") > 0);
    assert (compareVersions ("3.0.0~rc2", "3.0.0") < 0);

    assert (compareVersions ("4:5.6-2", "8.0-6") > 0);
    assert (compareVersions ("1:1.0-4", "3:0.8-2") < 0);

    assert (compareVersions ("5.9.1+dfsg-5pureos1", "5.9.1+dfsg-5") > 0);
}
