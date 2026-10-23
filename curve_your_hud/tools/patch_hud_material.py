import argparse
import copy
import ctypes
import json
import pathlib
import struct
import subprocess
import zlib


MASK64 = (1 << 64) - 1


def murmur64(data: bytes, seed: int = 0) -> int:
    m = 0xC6A4A7935BD1E995
    r = 47
    h = (seed ^ (len(data) * m)) & MASK64
    p = 0
    remaining = len(data)
    while remaining >= 8:
        k = struct.unpack_from("<Q", data, p)[0]
        k = (k * m) & MASK64
        k ^= k >> r
        k = (k * m) & MASK64
        h ^= k
        h = (h * m) & MASK64
        p += 8
        remaining -= 8
    for i in range(remaining):
        h ^= data[p + i] << (8 * i)
    if remaining:
        h = (h * m) & MASK64
    h ^= h >> r
    h = (h * m) & MASK64
    h ^= h >> r
    return h & MASK64


def id64(name: str) -> int:
    return murmur64(name.encode("utf-8"))


def id32(name: str) -> int:
    return id64(name) >> 32


class Reader:
    def __init__(self, data: bytes, pos: int = 0, end: int | None = None):
        self.data = data
        self.pos = pos
        self.end = len(data) if end is None else end

    def take(self, size: int) -> bytes:
        if size < 0 or self.pos + size > self.end:
            raise ValueError("truncated binary data")
        value = self.data[self.pos : self.pos + size]
        self.pos += size
        return value

    def u8(self) -> int:
        return self.take(1)[0]

    def u32(self) -> int:
        return struct.unpack("<I", self.take(4))[0]

    def u64(self) -> int:
        return struct.unpack("<Q", self.take(8))[0]

    def words(self, width: int) -> list[list[int]]:
        count = self.u32()
        return [[self.u32() for _ in range(width)] for _ in range(count)]


class Writer:
    def __init__(self):
        self.data = bytearray()

    def u8(self, value: int):
        self.data += struct.pack("<B", value)

    def u32(self, value: int):
        self.data += struct.pack("<I", value)

    def u64(self, value: int):
        self.data += struct.pack("<Q", value)

    def raw(self, value: bytes | bytearray):
        self.data += value

    def words(self, rows: list[list[int]]):
        self.u32(len(rows))
        for row in rows:
            for value in row:
                self.u32(value)

    def pad4(self):
        self.data += bytes((-len(self.data)) & 3)


def parse_material(data: bytes) -> dict:
    r = Reader(data)
    header = [r.u32() for _ in range(7)]
    version, material_offset, material_size, shader_offset, shader_size, other_offset, other_size = header
    if version not in (60, 61, 62) or material_offset != 28:
        raise ValueError("unsupported material stream")
    material_end = material_offset + material_size
    if material_end > len(data):
        raise ValueError("invalid material payload")
    p = Reader(data, material_offset, material_end)
    result = {
        "version": version,
        "direct_shader_selector_hash": p.u32(),
        "shader_provider_material_hash": p.u64(),
        "parent_material_hash": p.u64(),
        "unknown_u32": [],
        "textures": [],
        "contexts": [],
        "variables": [],
        "variable_data": b"",
        "unknown_5": [],
        "unknown_8": [],
        "shader_blob": b"",
        "other_blob": b"",
    }
    result["unknown_u32"] = [p.u32() for _ in range(p.u32())]
    result["textures"] = [[p.u32(), p.u64()] for _ in range(p.u32())]
    result["contexts"] = [[p.u32(), p.u32()] for _ in range(p.u32())]
    result["variables"] = [[p.u32() for _ in range(5)] for _ in range(p.u32())]
    result["variable_data"] = p.take(p.u32())
    result["unknown_5"] = [p.take(5) for _ in range(p.u32())]
    result["unknown_8"] = [p.take(8) for _ in range(p.u32())]
    if p.pos != material_end:
        raise ValueError("unparsed material payload bytes")
    if shader_size:
        if shader_offset != material_end:
            raise ValueError("non-contiguous shader section")
        result["shader_blob"] = data[shader_offset : shader_offset + shader_size]
    if other_size:
        expected = shader_offset + shader_size
        if other_offset != expected:
            raise ValueError("non-contiguous auxiliary section")
        result["other_blob"] = data[other_offset : other_offset + other_size]
    end = material_end + shader_size + other_size
    if end != len(data):
        raise ValueError("unparsed material stream bytes")
    return result


def encode_material(material: dict) -> bytes:
    body = Writer()
    body.u32(material["direct_shader_selector_hash"])
    body.u64(material["shader_provider_material_hash"])
    body.u64(material["parent_material_hash"])
    body.u32(len(material["unknown_u32"]))
    for value in material["unknown_u32"]:
        body.u32(value)
    body.u32(len(material["textures"]))
    for name, resource in material["textures"]:
        body.u32(name)
        body.u64(resource)
    body.u32(len(material["contexts"]))
    for name, value in material["contexts"]:
        body.u32(name)
        body.u32(value)
    body.u32(len(material["variables"]))
    for row in material["variables"]:
        for value in row:
            body.u32(value)
    body.u32(len(material["variable_data"]))
    body.raw(material["variable_data"])
    body.u32(len(material["unknown_5"]))
    for row in material["unknown_5"]:
        body.raw(row)
    body.u32(len(material["unknown_8"]))
    for row in material["unknown_8"]:
        body.raw(row)

    material_offset = 28
    material_size = len(body.data)
    shader_blob = material["shader_blob"]
    other_blob = material["other_blob"]
    shader_offset = material_offset + material_size if shader_blob else 0xFFFFFFFF
    other_offset = shader_offset + len(shader_blob) if other_blob else 0xFFFFFFFF
    header = struct.pack(
        "<7I",
        material["version"],
        material_offset,
        material_size,
        shader_offset,
        len(shader_blob),
        other_offset,
        len(other_blob),
    )
    return header + body.data + shader_blob + other_blob


def read_states(r: Reader) -> list[list[int]]:
    return [[r.u32(), r.u8(), r.u32(), r.u32()] for _ in range(r.u32())]


def write_states(w: Writer, states: list[list[int]]):
    w.u32(len(states))
    for key, kind, value, extra in states:
        w.u32(key)
        w.u8(kind)
        w.u32(value)
        w.u32(extra)


def read_variant(r: Reader) -> dict:
    result = {
        "bytecode": r.take(r.u32()),
        "compression": r.u32(),
        "size": r.u32(),
        "hash": r.u64(),
        "constant_buffers": [r.words(6), r.words(6)],
        "resources": [r.words(7) for _ in range(5)],
        "static_samplers": r.words(4),
        "inputs": r.words(3),
        "sampler_arrays": r.words(4),
    }
    return result


def write_variant(w: Writer, variant: dict):
    w.u32(len(variant["bytecode"]))
    w.raw(variant["bytecode"])
    w.u32(variant["compression"])
    w.u32(variant["size"])
    w.u64(variant["hash"])
    for rows in variant["constant_buffers"]:
        w.words(rows)
    for rows in variant["resources"]:
        w.words(rows)
    w.words(variant["static_samplers"])
    w.words(variant["inputs"])
    w.words(variant["sampler_arrays"])


def read_pass(r: Reader) -> dict:
    result = {"render_states": read_states(r), "sampler_states": [], "stages": []}
    for _ in range(r.u32()):
        result["sampler_states"].append([r.u32(), read_states(r)])
    for _ in range(6):
        result["stages"].append([read_variant(r) for _ in range(r.u32())])
    result["records16"] = r.words(4)
    result["words"] = [r.u32() for _ in range(4)]
    result["stream_out"] = r.words(5)
    return result


def write_pass(w: Writer, shader_pass: dict):
    write_states(w, shader_pass["render_states"])
    w.u32(len(shader_pass["sampler_states"]))
    for name, states in shader_pass["sampler_states"]:
        w.u32(name)
        write_states(w, states)
    for variants in shader_pass["stages"]:
        w.u32(len(variants))
        for variant in variants:
            write_variant(w, variant)
    w.words(shader_pass["records16"])
    for value in shader_pass["words"]:
        w.u32(value)
    w.words(shader_pass["stream_out"])


def parse_shader_section(data: bytes) -> dict:
    if len(data) < 48:
        raise ValueError("shader section is truncated")
    h = struct.unpack_from("<12I", data)
    (
        version,
        name,
        contexts_offset,
        context_count,
        conditions_offset,
        default_offset,
        render_config_offset,
        render_config_count,
        shader_data_offset,
        shader_data_size,
        device_offset,
        device_size,
    ) = h
    if version != 0x2B:
        raise ValueError("unsupported shader section")
    result = {"version": version, "name": name, "contexts": []}
    r = Reader(data, contexts_offset, conditions_offset)
    for _ in range(context_count):
        result["contexts"].append({"name": r.u32(), "reserved": r.u32(), "shaders": r.words(2)})
    if r.pos != conditions_offset:
        raise ValueError("context section size mismatch")
    result["conditions"] = data[conditions_offset:render_config_offset]
    result["render_config"] = list(
        struct.unpack_from(f"<{render_config_count}Q", data, render_config_offset)
    ) if render_config_count else []

    r = Reader(data, shader_data_offset, shader_data_offset + shader_data_size)
    result["shader_data"] = []
    for _ in range(r.u32()):
        entry = {"name": r.u32(), "resource_size": r.u32(), "resources": r.words(4)}
        entry["constant_buffers"] = []
        for _ in range(r.u32()):
            entry["constant_buffers"].append(
                {"variables": r.words(5), "size": r.u32(), "offset": r.u32()}
            )
        entry["records"] = r.words(7)
        entry["passes"] = [
            [r.u32(), r.u64(), r.u32(), r.u8()] for _ in range(r.u32())
        ]
        entry["tail"] = [r.u32(), r.u32()]
        result["shader_data"].append(entry)
    if r.pos != shader_data_offset + shader_data_size:
        raise ValueError("shader data size mismatch")

    r = Reader(data, device_offset, device_offset + device_size)
    result["device_data"] = []
    for _ in range(r.u32()):
        device = {"groups": []}
        for _ in range(r.u32()):
            device["groups"].append([read_pass(r) for _ in range(r.u32())])
        device["tail"] = r.u32()
        result["device_data"].append(device)
    if r.pos != device_offset + device_size:
        raise ValueError("device data size mismatch")
    result["default_data"] = data[default_offset:]
    return result


def encode_shader_section(section: dict) -> bytes:
    w = Writer()
    w.raw(bytes(48))
    contexts_offset = len(w.data)
    for context in section["contexts"]:
        w.u32(context["name"])
        w.u32(context["reserved"])
        w.words(context["shaders"])
    conditions_offset = len(w.data)
    w.raw(section["conditions"])
    render_config_offset = len(w.data)
    for value in section["render_config"]:
        w.u64(value)
    shader_data_offset = len(w.data)
    w.u32(len(section["shader_data"]))
    for entry in section["shader_data"]:
        w.u32(entry["name"])
        w.u32(entry["resource_size"])
        w.words(entry["resources"])
        w.u32(len(entry["constant_buffers"]))
        for cb in entry["constant_buffers"]:
            w.words(cb["variables"])
            w.u32(cb["size"])
            w.u32(cb["offset"])
        w.words(entry["records"])
        w.u32(len(entry["passes"]))
        for layer, sort_key, value, instanced in entry["passes"]:
            w.u32(layer)
            w.u64(sort_key)
            w.u32(value)
            w.u8(instanced)
        for value in entry["tail"]:
            w.u32(value)
    shader_data_size = len(w.data) - shader_data_offset
    w.pad4()
    device_offset = len(w.data)
    w.u32(len(section["device_data"]))
    for device in section["device_data"]:
        w.u32(len(device["groups"]))
        for group in device["groups"]:
            w.u32(len(group))
            for shader_pass in group:
                write_pass(w, shader_pass)
        w.u32(device["tail"])
    device_size = len(w.data) - device_offset
    w.pad4()
    default_offset = len(w.data)
    w.raw(section["default_data"])
    header = struct.pack(
        "<12I",
        section["version"],
        section["name"],
        contexts_offset,
        len(section["contexts"]),
        conditions_offset,
        default_offset,
        render_config_offset,
        len(section["render_config"]),
        shader_data_offset,
        shader_data_size,
        device_offset,
        device_size,
    )
    w.data[:48] = header
    return bytes(w.data)


def oodle_compress(dll_path: pathlib.Path, source: bytes) -> bytes:
    oodle = ctypes.WinDLL(str(dll_path))
    bound = oodle.OodleLZ_GetCompressedBufferSizeNeeded
    bound.argtypes = [ctypes.c_int, ctypes.c_longlong]
    bound.restype = ctypes.c_size_t
    compress = oodle.OodleLZ_Compress
    compress.argtypes = [
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_longlong,
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_longlong,
    ]
    compress.restype = ctypes.c_longlong
    capacity = bound(8, len(source))
    src = ctypes.create_string_buffer(source)
    dst = ctypes.create_string_buffer(capacity)
    written = compress(8, src, len(source), dst, 4, None, None, None, None, 0)
    if written <= 0 or written > capacity:
        raise RuntimeError("Oodle compression failed")
    return dst.raw[:written]


def append_material_variable(base: dict, donor: dict, name: str):
    name_hash = id32(name)
    if any(row[2] == name_hash for row in base["variables"]):
        return
    donor_row = next(row for row in donor["variables"] if row[2] == name_hash)
    width = (4, 8, 12, 16)[donor_row[0]]
    donor_offset = donor_row[3]
    value = donor["variable_data"][donor_offset : donor_offset + width]
    new_offset = len(base["variable_data"])
    base["variable_data"] += value
    row = donor_row.copy()
    row[3] = new_offset
    base["variables"].append(row)


def append_shader_variable(base_section: dict, donor_section: dict, name: str):
    name_hash = id32(name)
    donor_row = None
    for entry in donor_section["shader_data"]:
        for cb in entry["constant_buffers"]:
            for row in cb["variables"]:
                if row[2] == name_hash:
                    donor_row = row.copy()
                    break
    if donor_row is None:
        raise ValueError(f"{name} was not found in donor shader reflection")
    for entry in base_section["shader_data"]:
        target = next((cb for cb in entry["constant_buffers"] if cb["size"] == 336), None)
        if target is None:
            raise ValueError("base shader has no 336-byte per-object constant buffer")
        if not any(row[2] == name_hash for row in target["variables"]):
            target["variables"].append(donor_row.copy())


def copy_sampler_state(base_section: dict, donor_section: dict, name: str):
    name_hash = id32(name)
    donor_states = []
    for device in donor_section["device_data"]:
        for group in device["groups"]:
            for shader_pass in group:
                for sampler_name, states in shader_pass["sampler_states"]:
                    if sampler_name == name_hash:
                        donor_states.append(copy.deepcopy(states))
    if not donor_states:
        raise ValueError(f"{name} sampler state was not found in donor shader")
    if any(states != donor_states[0] for states in donor_states[1:]):
        raise ValueError(f"{name} sampler state is inconsistent across donor passes")

    replaced = 0
    for device in base_section["device_data"]:
        for group in device["groups"]:
            for shader_pass in group:
                for index, (sampler_name, _) in enumerate(shader_pass["sampler_states"]):
                    if sampler_name == name_hash:
                        shader_pass["sampler_states"][index] = (
                            sampler_name,
                            copy.deepcopy(donor_states[0]),
                        )
                        replaced += 1
    if not replaced:
        raise ValueError(f"{name} sampler state was not found in base shader")


def make_material_header(resource_name: str, stream_name: str) -> bytes:
    encoded = stream_name.encode("ascii")
    if not encoded or len(encoded) > 30:
        raise ValueError("material stream name must contain 1-30 ASCII bytes")
    out = bytearray(68)
    struct.pack_into("<Q", out, 0, id64("material"))
    struct.pack_into("<Q", out, 8, id64(resource_name))
    struct.pack_into("<I", out, 16, 1)
    out[28] = 1
    struct.pack_into("<I", out, 29, 30)
    struct.pack_into("<I", out, 33, 1)
    out[38 : 38 + len(encoded)] = encoded
    return bytes(out)


def crc32(data: bytes) -> str:
    return f"{zlib.crc32(data) & 0xFFFFFFFF:08x}"


def write_build_json(output: pathlib.Path, resource_name: str, header_name: str, header: bytes,
                     stream_name: str, stream: bytes):
    resource = {"type": "material", "name": resource_name}
    file_entry = {"path": header_name, "size": len(header), "crc32": crc32(header)}
    stream_file = {"path": stream_name, "size": len(stream), "crc32": crc32(stream)}
    manifest = {
        "schema": 1,
        "requested_output": "all",
        "selected_scene": 0,
        "requested_clip": None,
        "emitted_clips": [],
        "applied_approximations": [],
        "texture_dimension_normalizations": [],
        "memory": {"loaded_bytes": len(header) + len(stream), "game_copy_bytes": 0, "streamed_bytes": 0},
        "compiler": {"name": "curve_your_hud shader patcher", "version": "1"},
        "target": {"id": "darktide", "name": "Warhammer 40,000: Darktide", "unit_version": 115, "material_version": 61},
        "roots": [resource],
        "artifacts": [
            {"resource": resource, "role": "primary", "path": header_name, "size": len(header)},
            {"resource": resource, "role": "stream", "path": stream_name, "size": len(stream)},
        ],
        "resources": [
            {
                "key": resource,
                "name_hash": f"{id64(resource_name):016x}",
                "file": file_entry,
                "stream": {"name": stream_name, "file": stream_file},
                "dependencies": [],
            }
        ],
        "external_resources": [],
    }
    (output / "build.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=pathlib.Path, required=True)
    parser.add_argument("--donor", type=pathlib.Path, required=True)
    parser.add_argument("--dxbc", type=pathlib.Path, required=True)
    parser.add_argument("--oodle", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--resource", default="content/mods/curve_your_hud/hud_curve_clean")
    args = parser.parse_args()

    base_bytes = args.base.read_bytes()
    donor_bytes = args.donor.read_bytes()
    base = parse_material(base_bytes)
    donor = parse_material(donor_bytes)
    if encode_material(base) != base_bytes or encode_material(donor) != donor_bytes:
        raise ValueError("material stream did not survive a byte-exact parse/encode round trip")
    base_section = parse_shader_section(base["shader_blob"])
    donor_section = parse_shader_section(donor["shader_blob"])
    if encode_shader_section(base_section) != base["shader_blob"]:
        raise ValueError("base shader section did not survive a byte-exact round trip")
    if encode_shader_section(donor_section) != donor["shader_blob"]:
        raise ValueError("donor shader section did not survive a byte-exact round trip")

    for name in ("strength", "angular_strength"):
        append_material_variable(base, donor, name)
        append_shader_variable(base_section, donor_section, name)

    # The no-curve material uses a different filter mode for its source
    # render target. Copy the curved material's source sampler so implicit
    # derivatives actually produce the same smooth filtered result.
    copy_sampler_state(base_section, donor_section, "source")

    # The vanilla buffers already reserve the final eight bytes. Install the
    # donor defaults in the shader provider's default c_per_object data too.
    defaults = bytearray(base_section["default_data"])
    donor_defaults = donor_section["default_data"]
    if len(defaults) >= 336 and len(donor_defaults) >= 336:
        defaults[328:336] = donor_defaults[328:336]
    base_section["default_data"] = bytes(defaults)

    dxbc = args.dxbc.read_bytes()
    packed = oodle_compress(args.oodle, dxbc)
    replaced = 0
    for device in base_section["device_data"]:
        for group in device["groups"]:
            for shader_pass in group:
                if len(shader_pass["stages"][4]) != 1:
                    raise ValueError("expected exactly one pixel variant per pass")

                # Keep the complete vanilla reflection record. Darktide uses its
                # bindless SRV/UAV/sampler entries when constructing the D3D12 root
                # signature even when the replacement pixel bytecode does not read
                # those resources. Only the bytecode payload itself changes.
                new_variant = copy.deepcopy(shader_pass["stages"][4][0])
                new_variant["bytecode"] = packed
                new_variant["compression"] = 5
                new_variant["size"] = len(dxbc)
                new_variant["hash"] = murmur64(packed)
                shader_pass["stages"][4][0] = copy.deepcopy(new_variant)
                replaced += 1
    if not replaced:
        raise ValueError("base material contained no pixel shader")

    # Keep the base material texture records. The replacement shader restores
    # the raster-intensity and variation branches, which read three of those
    # bindless textures while leaving the other effect branches disabled.
    base["shader_blob"] = encode_shader_section(base_section)
    output_stream = encode_material(base)
    reparsed = parse_material(output_stream)
    if encode_material(reparsed) != output_stream:
        raise ValueError("patched material failed round-trip validation")

    args.output.mkdir(parents=True, exist_ok=True)
    header_name = "hud_curve_clean.material"
    stream_leaf = f"{murmur64((args.resource + '|stream').encode()):016x}"
    stream_name = f"data/am/{stream_leaf}"
    header = make_material_header(args.resource, stream_name)
    stream_path = args.output / stream_name
    stream_path.parent.mkdir(parents=True, exist_ok=True)
    (args.output / header_name).write_bytes(header)
    stream_path.write_bytes(output_stream)
    write_build_json(args.output, args.resource, header_name, header, stream_name, output_stream)

    print(json.dumps({
        "resource": args.resource,
        "pixel_dxbc_bytes": len(dxbc),
        "pixel_kraken_bytes": len(packed),
        "material_stream_bytes": len(output_stream),
        "replaced_pixel_variants": replaced,
        "strength_hash": f"{id32('strength'):08x}",
        "angular_strength_hash": f"{id32('angular_strength'):08x}",
    }, indent=2))


if __name__ == "__main__":
    main()
