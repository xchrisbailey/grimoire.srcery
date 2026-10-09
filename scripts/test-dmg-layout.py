#!/usr/bin/env python3
"""Checks scripts/dmg-layout.py by reading back what it writes, with a small
independent reader of the .DS_Store format. Standard library only.

Run from the repo root:  python3 scripts/test-dmg-layout.py
"""
import importlib.util
import json
import os
import plistlib
import shutil
import struct
import tempfile
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
spec = importlib.util.spec_from_file_location("dmg_layout", os.path.join(HERE, "dmg-layout.py"))
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)

with open(os.path.join(ROOT, "Brand", "dmg-layout.json")) as handle:
    CONFIG = json.load(handle)


def block(data, address):
    offset, width = address & ~0x1F, address & 0x1F
    return data[4 + offset:4 + offset + (1 << width)]


def read_store(data):
    """Returns (records, free list sizes) read through the buddy allocator's tables."""
    magic, tag, offset, size, offset2 = struct.unpack_from(">I4sIII", data, 0)
    assert (magic, tag, offset, offset2) == (1, b"Bud1", 2048, 2048)
    root = data[4 + offset:4 + offset + size]
    count, _ = struct.unpack_from(">II", root, 0)
    addresses = struct.unpack_from(">%dI" % count, root, 8)
    position = 8 + 4 * 256
    (toc_count,) = struct.unpack_from(">I", root, position)
    position += 4
    toc = {}
    for _ in range(toc_count):
        length = root[position]
        name = root[position + 1:position + 1 + length]
        (toc[name],) = struct.unpack_from(">I", root, position + 1 + length)
        position += 5 + length
    free = []
    for _ in range(32):
        (n,) = struct.unpack_from(">I", root, position)
        free.append(list(struct.unpack_from(">%dI" % n, root, position + 4)))
        position += 4 + 4 * n
    header = block(data, addresses[toc[b"DSDB"]])
    node_id, levels, records, nodes, page = struct.unpack_from(">IIIII", header, 0)
    assert (levels, nodes, page) == (0, 1, 4096)
    node = block(data, addresses[node_id])
    leaf, n = struct.unpack_from(">II", node, 0)
    assert leaf == 0 and n == records
    position, found = 8, []
    for _ in range(n):
        (chars,) = struct.unpack_from(">I", node, position)
        name = node[position + 4:position + 4 + 2 * chars].decode("utf-16-be")
        position += 4 + 2 * chars
        code, kind = node[position:position + 4], node[position + 4:position + 8]
        position += 8
        if kind == b"blob":
            (length,) = struct.unpack_from(">I", node, position)
            value = node[position + 4:position + 4 + length]
            position += 4 + length
        elif kind == b"long":
            (value,) = struct.unpack_from(">I", node, position)
            position += 4
        elif kind == b"type":
            value = node[position:position + 4]
            position += 4
        else:
            raise AssertionError("unexpected record type %r" % kind)
        found.append((name, code, value))
    return found, free


class LayoutTests(unittest.TestCase):
    def make_volume(self, with_readme):
        volume = tempfile.mkdtemp(prefix="Grimoire test ")
        self.addCleanup(lambda: shutil.rmtree(volume, ignore_errors=True))
        os.mkdir(os.path.join(volume, ".background"))
        open(os.path.join(volume, ".background", "background.tiff"), "wb").close()
        os.mkdir(os.path.join(volume, "Grimoire.app"))
        os.symlink("/Applications", os.path.join(volume, "Applications"))
        if with_readme:
            open(os.path.join(volume, "Read me first.txt"), "w").close()
        return os.path.realpath(volume)

    def written(self, with_readme=True):
        volume = self.make_volume(with_readme)
        names = set(os.listdir(volume))
        return volume, read_store(layout.store(layout.records(CONFIG, volume, names)))

    def test_window_is_fixed_size_icon_view_without_chrome(self):
        _, (found, _) = self.written()
        root = {code: value for name, code, value in found if name == "."}
        bwsp = plistlib.loads(root[b"bwsp"])
        window = CONFIG["window"]
        self.assertEqual(
            bwsp["WindowBounds"],
            "{{%d, %d}, {%d, %d}}" % (window["x"], window["y"], window["width"], window["height"]))
        for key in ("ShowToolbar", "ShowSidebar", "ShowStatusBar", "ShowPathbar", "ShowTabView"):
            self.assertIs(bwsp[key], False, key)
        self.assertEqual(root[b"icvl"], b"icnv")
        icvp = plistlib.loads(root[b"icvp"])
        self.assertEqual(icvp["backgroundType"], 2)
        self.assertEqual(icvp["iconSize"], float(CONFIG["iconSize"]))
        self.assertEqual(icvp["arrangeBy"], "none")

    def test_icons_sit_where_the_layout_says(self):
        _, (found, _) = self.written()
        places = {
            name: struct.unpack(">II", value[:8])
            for name, code, value in found if code == b"Iloc"
        }
        self.assertEqual(
            places, {name: tuple(point) for name, point in CONFIG["icons"].items()})

    def test_read_me_is_placed_only_when_the_image_has_one(self):
        _, (found, _) = self.written(with_readme=False)
        names = {name for name, code, _ in found if code == b"Iloc"}
        self.assertEqual(names, {"Grimoire.app", "Applications"})

    def test_read_me_stays_off_the_artwork_centre_row(self):
        row = CONFIG["icons"]["Grimoire.app"][1]
        note = CONFIG["icons"]["Read me first.txt"]
        self.assertGreater(note[1] - row, CONFIG["iconSize"])

    def test_entries_are_ordered_and_free_space_excludes_the_used_blocks(self):
        _, (found, free) = self.written()
        names = [name for name, _, _ in found]
        self.assertEqual(names, sorted(names, key=str.lower))
        self.assertEqual((free[5], free[11], free[12]), ([], [], []))

    def test_alias_points_at_the_background_on_the_volume(self):
        volume, (found, _) = self.written()
        icvp = plistlib.loads(next(v for n, c, v in found if c == b"icvp"))
        alias = icvp["backgroundImageAlias"]
        size, version = struct.unpack_from(">hh", alias, 4)
        self.assertEqual((size, version), (len(alias), 2))
        self.assertIn(b"/.background/background.tiff", alias)
        self.assertIn(os.path.basename(volume).encode(), alias)


if __name__ == "__main__":
    unittest.main()
