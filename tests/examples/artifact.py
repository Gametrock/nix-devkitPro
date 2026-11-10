"""Validate console container headers and section bounds without running target code"""

from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
data = path.read_bytes()

assert data, f"Empty artifact: {path}"


def u32(offset):
    return struct.unpack_from("<I", data, offset)[0]


def region(offset, size):
    assert size > 0 and offset >= 0 and offset + size <= len(data), (
        path,
        offset,
        size,
        len(data),
    )


suffix = path.suffix
if suffix == ".gba":
    assert len(data) >= 0xC0
    assert data[4:8] == b"\x24\xff\xae\x51"
    assert data[0xB2] == 0x96
    assert data[0xBD] == (-sum(data[0xA0:0xBD]) - 0x19) & 0xFF

elif suffix == ".nds":
    assert len(data) >= 0x160
    assert data[0xC0:0xC4] == b"\x24\xff\xae\x51"

    region(u32(0x20), u32(0x2C))  # ARM9 image
    region(u32(0x30), u32(0x3C))  # ARM7 image

    crc = 0xFFFF
    for byte in data[:0x15E]:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0xA001 if crc & 1 else 0)

    assert crc == struct.unpack_from("<H", data, 0x15E)[0]

elif suffix == ".3dsx":
    assert data[:4] == b"3DSX" and len(data) >= 0x20

    assert struct.unpack_from("<H", data, 4)[0] >= 0x20

elif suffix == ".dol":
    assert len(data) >= 0x100
    offsets = struct.unpack_from(">18I", data, 0)
    addresses = struct.unpack_from(">18I", data, 0x48)
    sizes = struct.unpack_from(">18I", data, 0x90)

    assert any(sizes)
    for offset, address, size in zip(offsets, addresses, sizes):
        if size:
            assert offset >= 0x100 and address != 0
            region(offset, size)

    assert struct.unpack_from(">I", data, 0xE0)[0] != 0

elif suffix == ".rpx":
    assert data[:4] == b"\x7fELF" and data[4:6] == b"\x01\x02"
    assert struct.unpack_from(">H", data, 18)[0] == 20

elif suffix == ".nro":
    assert data[0x10:0x14] == b"NRO0"
    core_size = u32(0x18)
    region(0, core_size)

    for offset in (0x20, 0x28, 0x30):
        start, size = struct.unpack_from("<II", data, offset)
        region(start, size)

    if "--romfs" in sys.argv:
        assert data[core_size : core_size + 4] == b"ASET"
        offset, size = struct.unpack_from("<QQ", data, core_size + 0x28)
        region(core_size + offset, size)

elif suffix == ".nsp":
    assert data[:4] == b"PFS0"
    count, names_size = struct.unpack_from("<II", data, 4)

    assert count >= 2
    names_start = 0x10 + count * 0x18
    content_start = names_start + names_size
    names = data[names_start:content_start]
    members = {}

    for index in range(count):
        entry_offset = 0x10 + index * 0x18
        offset, size, name_offset = struct.unpack_from("<QQI", data, entry_offset)
        assert name_offset < len(names)
        name = names[name_offset:].split(b"\0", 1)[0].decode()

        region(content_start + offset, size)
        members[name] = data[content_start + offset : content_start + offset + size]

    assert members["main"][:4] == b"NSO0"
    assert members["main.npdm"][:4] == b"META"

else:
    raise ValueError(f"Unsupported console artifact: {path}")

print(
    f"Validated {path.name}: container header, payload bounds, and applicable checksums"
)
