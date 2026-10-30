#!/usr/bin/env python3
"""Shrinks the textures embedded in a .glb to PS1 size and repacks the file.

Every image is resized so its longest side is at most --max px (power of two, box filter) and
re-encoded as PNG; the binary chunk is rebuilt so bufferView offsets stay valid. Geometry and
animation data are copied untouched.

    python3 tools/psx_glb.py in.glb out.glb [--max 128]
    python3 tools/psx_glb.py --info in.glb      # node names, triangle count, image sizes
"""
import argparse
import io
import json
import struct

from PIL import Image


def read_glb(path: str) -> tuple[dict, bytes]:
    data = open(path, "rb").read()
    magic, _version, _length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF", "not a binary glTF"
    off = 12
    js, binary = None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8:off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(chunk)
        elif ctype == b"BIN\0":
            binary = chunk
        off += 8 + clen
    return js, binary


def write_glb(path: str, js: dict, binary: bytes) -> None:
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * (-len(jb) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(jb) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(jb), b"JSON") + jb)
        f.write(struct.pack("<I4s", len(binary), b"BIN\0") + binary)


def view_bytes(js: dict, binary: bytes, index: int) -> bytes:
    bv = js["bufferViews"][index]
    start = bv.get("byteOffset", 0)
    return binary[start:start + bv["byteLength"]]


def shrink(js: dict, binary: bytes, max_px: int) -> tuple[dict, bytes]:
    replaced = {}
    for img in js.get("images", []):
        if "bufferView" not in img:
            continue
        im = Image.open(io.BytesIO(view_bytes(js, binary, img["bufferView"])))
        im.load()
        w, h = im.size
        scale = min(1.0, max_px / max(w, h))
        nw = 1 << max(2, round(w * scale).bit_length() - 1)
        nh = 1 << max(2, round(h * scale).bit_length() - 1)
        mode = "RGBA" if im.mode in ("RGBA", "LA", "P") and "A" in im.getbands() or im.mode == "P" else "RGB"
        im = im.convert(mode)
        if (nw, nh) != (w, h):
            im = im.resize((nw, nh), Image.BOX)
        out = io.BytesIO()
        im.save(out, "PNG", optimize=True)
        replaced[img["bufferView"]] = out.getvalue()
        img["mimeType"] = "image/png"
    # Rebuild the buffer: every view gets its (possibly new) bytes, 4-byte aligned.
    new_bin = bytearray()
    for i, bv in enumerate(js["bufferViews"]):
        chunk = replaced.get(i, view_bytes(js, binary, i))
        new_bin += b"\0" * (-len(new_bin) % 4)
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(chunk)
        bv["buffer"] = 0
        new_bin += chunk
    js["buffers"] = [{"byteLength": len(new_bin)}]
    return js, bytes(new_bin)


def info(path: str) -> None:
    js, binary = read_glb(path)
    tris = 0
    for mesh in js.get("meshes", []):
        for p in mesh["primitives"]:
            acc = js["accessors"][p["indices"]] if "indices" in p else js["accessors"][p["attributes"]["POSITION"]]
            tris += acc["count"] // 3
    print(f"{path}: {tris} triangles, {len(js.get('meshes', []))} meshes, {len(js.get('animations', []))} animations")
    for img in js.get("images", []):
        if "bufferView" in img:
            im = Image.open(io.BytesIO(view_bytes(js, binary, img["bufferView"])))
            print(f"  image {img.get('name', '')} {im.size} {im.mode}")

    def walk(i: int, depth: int) -> None:
        n = js["nodes"][i]
        mark = " [mesh]" if "mesh" in n else ""
        print("  " + "  " * depth + n.get("name", f"node{i}") + mark)
        for c in n.get("children", []):
            walk(c, depth + 1)

    for root in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(root, 0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--max", type=int, default=128)
    ap.add_argument("--info", action="store_true")
    a = ap.parse_args()
    if a.info:
        info(a.src)
    else:
        js, binary = read_glb(a.src)
        write_glb(a.dst, *shrink(js, binary, a.max))
