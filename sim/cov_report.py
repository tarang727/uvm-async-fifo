#!/usr/bin/env python3
"""
cov_report.py - summarize a Verilator coverage.dat (single run or merged).

Prints, per covergroup, how many bins were hit, and lists every unhit bin.
Also prints the SVA cover properties and their hit counts.

Only the covergroup and user (cover property) points are reported; line/toggle
coverage is not enabled in this flow.

Usage: python3 cov_report.py logs/merged.coverage.dat
"""
import re
import sys
from collections import defaultdict


def parse(path):
    """Yield (fields: dict, count: int) for every coverage point in the file.

    Each point is a line: C '<\\x01key\\x02value ...>' <count>
    """
    point_re = re.compile(r"^C '(.*)' (\d+)$")
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = point_re.match(line.rstrip("\n"))
            if not m:
                continue
            fields = {}
            for kv in m.group(1).split("\x01"):
                if "\x02" in kv:
                    k, v = kv.split("\x02", 1)
                    fields[k] = v
            yield fields, int(m.group(2))


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    groups = defaultdict(list)   # covergroup -> [(bin hierarchy, count)]
    covers = []                  # [(cover property name, count)]

    for f, count in parse(sys.argv[1]):
        kind = f.get("t")
        if kind == "covergroup":
            # Skip ignore/illegal bins if any are ever added.
            if f.get("Bt") in ("ignore", "illegal"):
                continue
            hier = f.get("h", "?")
            group = hier.split(".")[0].split("::")[-1]
            groups[group].append((hier.split(".", 1)[-1], count))
        elif kind == "user":
            covers.append((f.get("o", f.get("h", "?")), count))

    total_bins = total_hit = 0
    print("Covergroup bins")
    print("-" * 72)
    for g in sorted(groups):
        bins = groups[g]
        hit = sum(1 for _, c in bins if c > 0)
        total_bins += len(bins)
        total_hit += hit
        print(f"{g:<16} {hit:>4}/{len(bins):<4} bins hit")
        for name, c in sorted(bins):
            if c == 0:
                print(f"    UNHIT  {name}")
    if total_bins:
        print("-" * 72)
        print(f"{'all groups':<16} {total_hit:>4}/{total_bins:<4} bins hit "
              f"({100.0 * total_hit / total_bins:.1f}% of bins)")

    if covers:
        print()
        print("SVA cover properties")
        print("-" * 72)
        for name, c in sorted(covers):
            print(f"{name:<28} {c:>8}{'' if c else '   <-- never hit'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
