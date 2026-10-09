#!/usr/bin/env python3
"""Writes the Finder window layout of a mounted disk image into its .DS_Store.

It writes the file itself, with no Finder, AppleScript or window server, so the
layout comes out the same on a headless CI runner as on a Mac with a logged-in user.
It uses only the standard library.

The image needs the artwork at .background/background.tiff already. The window
size and position and the icon positions come from Brand/dmg-layout.json: icon
view, no toolbar, status bar, path bar or sidebar, and the artwork as the background.

A .DS_Store is a buddy-allocator file holding a B-tree of (name, record) entries.
Everything here fits one leaf node, so this writes the fixed layout that gives:
the header at 0, the DSDB header block at 32, the root block at 2048 and the node at
4096 (offsets count from byte 4 of the file, as the format does).

The background is referenced by a Mac alias to the artwork on the mounted volume,
built from the file's real inode (the HFS+ catalog node ID), parent, creation date,
and the volume's name and creation date.

Usage: scripts/dmg-layout.py <mount point> <layout json>
"""
import json
import os
import plistlib
import struct
import sys

MAC_EPOCH_OFFSET = 2082844800  # seconds from 1904 to 1970
BACKGROUND = ".background/background.tiff"


def entry(name, code, kind, data):
    """One record: the file name, a four-letter code, a four-letter type, the value."""
    encoded = name.encode("utf-16-be")
    return struct.pack(">I", len(encoded) // 2) + encoded + code + kind + data


def blob(payload):
    return struct.pack(">I", len(payload)) + payload


def alias_for(path, mount):
    """A version 2 alias record to `path` on the volume mounted at `mount`."""
    st = os.stat(path)
    parent = os.stat(os.path.dirname(path))
    root = os.stat(mount)
    volume_name = os.path.basename(mount)
    filename = os.path.basename(path)
    relative = "/" + os.path.relpath(path, mount)
    carbon = volume_name + ":" + ":\0".join(relative.strip("/").split("/"))

    def date(stat):
        return int(stat.st_birthtime) + MAC_EPOCH_OFFSET

    def tag(number, value):
        padded = value + (b"\0" if len(value) % 2 else b"")
        return struct.pack(">hh", number, len(value)) + padded

    def utf16(text):
        encoded = text.encode("utf-16-be")
        return struct.pack(">h", len(encoded) // 2) + encoded

    body = struct.pack(
        ">h28pI2shI64pII4s4shhI2s10s",
        0,  # a file
        volume_name.encode("utf-8"),
        date(root),
        b"H+",
        0,  # a fixed disk
        parent.st_ino,
        filename.encode("utf-8"),
        st.st_ino,
        date(st),
        b"\0\0\0\0",
        b"\0\0\0\0",
        -1,
        -1,
        0,
        b"\0\0",
        b"",
    )
    body += tag(0, os.path.basename(os.path.dirname(path)).encode("utf-8"))
    body += struct.pack(
        ">hhQhhQ", 16, 8, date(root) << 16, 17, 8, date(st) << 16
    )
    body += tag(1, struct.pack(">I", parent.st_ino))
    body += tag(2, carbon.encode("utf-8"))
    body += tag(14, utf16(filename))
    body += tag(15, utf16(volume_name))
    body += tag(18, relative.encode("utf-8"))
    body += tag(19, mount.encode("utf-8"))
    body += struct.pack(">hh", -1, 0)
    return b"\0\0\0\0" + struct.pack(">hh", 8 + len(body), 2) + body


def records(layout, mount, names):
    window = layout["window"]
    bounds = "{{%d, %d}, {%d, %d}}" % (
        window["x"], window["y"], window["width"], window["height"])
    bwsp = {
        "WindowBounds": bounds,
        "ShowStatusBar": False,
        "ShowPathbar": False,
        "ShowToolbar": False,
        "ShowTabView": False,
        "ShowSidebar": False,
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
    }
    icvp = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundImageAlias": alias_for(os.path.join(mount, BACKGROUND), mount),
        "backgroundColorRed": 0.0,
        "backgroundColorGreen": 0.0,
        "backgroundColorBlue": 0.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": float(layout["textSize"]),
        "iconSize": float(layout["iconSize"]),
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }
    found = [
        entry(".", b"bwsp", b"blob", blob(plistlib.dumps(bwsp, fmt=plistlib.FMT_BINARY))),
        entry(".", b"icvl", b"type", b"icnv"),
        entry(".", b"icvp", b"blob", blob(plistlib.dumps(icvp, fmt=plistlib.FMT_BINARY))),
        entry(".", b"vSrn", b"long", struct.pack(">I", 1)),
    ]
    by_name = {}
    for name, (x, y) in layout["icons"].items():
        if name in names:
            location = struct.pack(">IIIHH", x, y, 0xFFFFFFFF, 0xFFFF, 0)
            by_name[name] = entry(name, b"Iloc", b"blob", blob(location))
    # Finder looks entries up by name, ignoring case.
    return found + [by_name[name] for name in sorted(by_name, key=str.lower)]


def store(entries):
    """The whole .DS_Store file for a single-node tree holding `entries`."""
    node = struct.pack(">II", 0, len(entries)) + b"".join(entries)
    assert len(node) <= 4096, "too many entries for one node"
    node = node.ljust(4096, b"\0")
    dsdb = struct.pack(">IIIII", 2, 0, len(entries), 1, 4096).ljust(32, b"\0")

    # Free space: every power of two the initial 2 GB region splits into, less
    # the four blocks used (32 at 0, 32 at 32, 2048, 4096).
    free = {n: [1 << n] for n in range(5, 31)}
    free[5] = []
    free[11] = []
    free[12] = []
    free[31] = []
    offsets = [2048 | 11, 32 | 5, 4096 | 12]
    root = struct.pack(">II", len(offsets), 0)
    root += struct.pack(">256I", *(offsets + [0] * (256 - len(offsets))))
    root += struct.pack(">I", 1) + bytes([4]) + b"DSDB" + struct.pack(">I", 1)
    for width in range(32):
        root += struct.pack(">I", len(free.get(width, [])))
        root += b"".join(struct.pack(">I", offset) for offset in free.get(width, []))
    root = root.ljust(2048, b"\0")

    header = struct.pack(">I4sIII16s", 1, b"Bud1", 2048, 2048, 2048,
                         b"\x00\x00\x10\x0c\x00\x00\x00\x87\x00\x00\x20\x0b\x00\x00\x00\x00")
    # Buddy offsets start 4 bytes into the file; blocks are zero-filled between.
    image = bytearray(4 + 4096 + 4096)
    image[0:len(header)] = header
    image[4 + 32:4 + 32 + len(dsdb)] = dsdb
    image[4 + 2048:4 + 2048 + len(root)] = root
    image[4 + 4096:4 + 4096 + len(node)] = node
    return bytes(image)


def main():
    mount, layout_path = sys.argv[1:3]
    with open(layout_path) as handle:
        layout = json.load(handle)
    mount = os.path.realpath(mount)
    names = {name for name in os.listdir(mount)}
    missing = [name for name in layout["icons"] if name not in names]
    # Read me first.txt exists only on ad-hoc builds.
    missing = [name for name in missing if name != "Read me first.txt"]
    if missing or not os.path.exists(os.path.join(mount, BACKGROUND)):
        sys.exit("dmg-layout: the image lacks %s" % (", ".join(missing) or BACKGROUND))
    with open(os.path.join(mount, ".DS_Store"), "wb") as handle:
        handle.write(store(records(layout, mount, names)))


if __name__ == "__main__":
    main()
