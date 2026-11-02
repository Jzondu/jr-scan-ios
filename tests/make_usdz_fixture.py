"""Create a tiny uncompressed USDZ with its file data aligned to 64 bytes."""
from pathlib import Path
import struct
import zipfile

destination = Path("build/geometry-fixture.usdz")
destination.parent.mkdir(exist_ok=True)
name = "fixture.usda"
padding = (-(30 + len(name.encode()))) % 64
if padding < 4:
    padding += 64
info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
info.compress_type = zipfile.ZIP_STORED
info.extra = struct.pack("<HH", 0xFFFF, padding - 4) + bytes(padding - 4)
with zipfile.ZipFile(destination, "w") as archive:
    archive.writestr(info, Path("tests/fixture.usda").read_bytes())
