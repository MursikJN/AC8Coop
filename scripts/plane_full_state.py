"""Offline AC8 logical full-state mapping. No game/process/network access.

Offsets label fields in native caches, NOT a C++ object serialization. No vtables,
shared ownership, array descriptors, actor identities, dirty flags or live writes
are manufactured. Native arithmetic is traced to build 25201480 disassembly.
CRT asinf is represented by rounded Python asin; bit-identical CRT output is NOT
claimed. Angle components retain native order: no guessed yaw/pitch/roll labels.
"""
import math
import struct

BUILD = 25201480
DEGREES = 57.29577951308232
DIRECTION_THRESHOLD = 9.99999993922529e-09
INPUT_EPSILON = 9.999999747378752e-05
SCHEMA = {
    "0x38": (3, "d"), "0x60": (2, "f"), "0x108": (1, "f"),
    "0x124": (3, "B"), "0x128": (3, "d"), "0x140": (7, "f"),
    "0x160": (6, "d"), "0x1e0": (3, "d"), "0x1f8": (3, "d"),
    "0x210": (3, "d"), "0x868": (1, "B"), "0x8b0": (1, "I"),
    "0x8f8": (4, "f"), "0x908": (3, "d"), "0x920": (4, "f"),
    "0x930": (3, "d"),
}


def f32(value):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError("expected finite scalar")
    try:
        result = struct.unpack("<f", struct.pack("<f", value))[0]
    except (OverflowError, struct.error) as exc:
        raise ValueError("float32 overflow") from exc
    if not math.isfinite(result):
        raise ValueError("float32 overflow")
    return result


def _uint(value, bits):
    if type(value) is not int or not 0 <= value < 1 << bits:
        raise ValueError("invalid unsigned integer")
    return value


def _fields(row):
    fields = row["fields"]
    result = {}
    for name, (count, kind) in SCHEMA.items():
        values = fields[name]["values"]
        if len(values) != count:
            raise ValueError("incorrect field component count: " + name)
        if kind in ("B", "I"):
            values = tuple(_uint(v, 8 if kind == "B" else 32) for v in values)
        else:
            if not all(type(v) in (int, float) and math.isfinite(v) for v in values):
                raise ValueError("nonfinite source field: " + name)
            values = tuple(f32(v) if kind == "f" else float(v) for v in values)
        result[name] = values
    return result


def native_atan2_approx(y, x):
    """Instruction-rounded polynomial at RVA16ee4a0, finite inputs only."""
    y, x = f32(y), f32(x)
    ay, ax = abs(y), abs(x)
    swap = ay > ax
    low, high = (ax, ay) if swap else (ay, ax)
    if high == 0:
        return 0.0
    ratio = f32(low / high)
    square = f32(ratio * ratio)
    poly = f32(square * 0.0072128851898014545)
    for op, coefficient in (
        (-1, 0.03505967929959297), (1, 0.08167587965726852),
        (-1, 0.13374657928943634), (1, 0.19856563210487366),
        (-1, 0.3332499861717224), (1, 1.0),
    ):
        poly = f32(poly + op * coefficient)
        if coefficient != 1.0:
            poly = f32(poly * square)
    angle = f32(ratio * poly)
    if swap:
        angle = f32(1.5707963705062866 - angle)
    if x < 0:
        angle = f32(3.1415927410125732 - angle)
    if y < 0:
        angle = -angle
    return angle


def native_angle_components(quaternion):
    """RVA4d318a0 operation order; returns three radians in native order.

    The asinf import is established by PE IAT, not assumed from convention.
    Python asin rounding may differ from the game's CRT at last bits.
    """
    if len(quaternion) != 4:
        raise ValueError("four quaternion components required")
    x, y, z, w = (f32(v) for v in quaternion)
    xx2 = f32(f32(x + x) * x)
    zw2 = f32(f32(w * z) * 2)
    xy2 = f32(f32(y * x) * 2)
    zz2 = f32(f32(z * z) * 2)
    third = native_atan2_approx(f32(zw2 + xy2), f32(1.0 - f32(zz2 + xx2)))
    yy2 = f32(f32(y * y) * 2)
    xz2 = f32(f32(x * z) * 2)
    yw2 = f32(f32(y * w) * 2)
    second = native_atan2_approx(f32(yw2 + xz2), f32(1.0 - f32(yy2 + xx2)))
    sine = f32(f32(f32(y * z) - f32(w * x)) * 2)
    sine = max(-1.0, min(1.0, sine))
    first = -f32(math.asin(sine))
    return first, second, third


def _axis(vector):
    return vector[2], -vector[0], vector[1]


def _float_fields(start, values):
    return {hex(start + 4 * i): f32(v) for i, v in enumerate(values)}


def _clamp32(value, lower, upper):
    return max(lower, min(upper, f32(value)))


def input_bit0(sources, model_flags):
    """RVA7d660f0. Nested snapshots omit raw pointers but preserve nullness.

    mode_object = None or {state_108, actor: None or {flag_b29,
                    child: None or {flag_10}}}.
    Missing is an error; None explicitly represents an observed null pointer.
    """
    flags = _uint(model_flags, 32)
    if flags & (1 << 17):
        return 0
    near = (abs(f32(f32(sources["0xfec"]) - 1.0)) < INPUT_EPSILON
            and abs(f32(f32(sources["0xff0"]) - 1.0)) < INPUT_EPSILON)
    mode = sources["mode_object"]
    if mode is not None:
        actor = mode["actor"]
        active = (_uint(mode["state_108"], 8) == 4
                  and (actor is None or _uint(actor["flag_b29"], 8) != 1))
        if actor is not None and actor["child"] is not None:
            active = _uint(actor["child"]["flag_10"], 8) != 0
        near = near or active
    return int(near or _uint(sources["0x1315"], 8) != 0
               or _uint(sources["0xffc"], 8) != 0)


def map_input(sources, model_flags):
    """Pre-flight input sources from actor offsets, not filtered model+0..18."""
    if _uint(sources["0x58dc"], 8) != 0:
        return {**_float_fields(8, [0] * 6), "0x20": 4}
    gain = f32(sources["0x6c8"])
    fe4, fe8 = f32(sources["0xfe4"]), f32(sources["0xfe8"])
    mode1313 = _uint(sources["0x1313"], 8) != 0
    values = (
        _clamp32(f32(sources["0xff8"]) * gain, -1.0, 1.0),
        _clamp32(f32(f32(sources["0xff0"]) - f32(sources["0xfec"])) * gain, -1.0, 1.0),
        _clamp32(f32(sources["0xff4"]) * gain, -1.0, 1.0),
        _clamp32(fe4, 0.0, 1.0), _clamp32(fe8, 0.0, 1.0),
        _clamp32(fe8 if mode1313 else f32(fe8 + fe4) * 0.5, 0.0, 1.0),
    )
    flags = (input_bit0(sources, model_flags) | (int(mode1313) << 1)
             | (int(_uint(sources["0x1314"], 8) != 0) << 2)
             | (int(_uint(sources["0x13d1"], 8) == 1) << 3)
             | (((model_flags >> 9) & 1) << 4))
    return {**_float_fields(8, values), "0x20": flags}


def native_timestamp(*, qpc_ticks, seconds_per_tick, clock08, clock18, clock20):
    """Observed native clock arithmetic, not inter-host synchronization.

    qpc_ticks must be observed in the same machine/clock domain as the fields.
    No epoch/sequence/wall-clock substitute is accepted. Caller owns freshness.
    """
    if type(qpc_ticks) is not int or not 0 <= qpc_ticks < 2**63:
        raise ValueError("invalid QPC value")
    if type(seconds_per_tick) not in (float, int) or not math.isfinite(seconds_per_tick) or seconds_per_tick <= 0:
        raise ValueError("invalid clock scale")
    _uint(clock08, 64)
    _uint(clock18, 64)
    if type(clock20) is not int or not -(2**63) <= clock20 < 2**63:
        raise ValueError("invalid signed clock adjustment")
    ticks = (float(qpc_ticks) * seconds_per_tick + 16777216.0) * 10000000.0
    if not math.isfinite(ticks) or not 0 <= ticks < 2**64:
        raise ValueError("native clock conversion overflow")
    return (clock18 - clock08 + math.trunc(ticks) + clock20) & (2**64 - 1)


def map_observation(row, *, input_sources=None, clock=None):
    """Return a full logical snapshot of known arithmetic, explicit missing parts.

    This does not reproduce sender dirty/delta policy, initialize native objects,
    or authorize an apply. A complete logical snapshot is not a rollback image.
    """
    f = _fields(row)
    # RVA dc4c03c is writable: PE default 10, native initialization sets 100.
    # Never substitute the file default for an absent runtime observation.
    scale = None
    missing = []
    if "position_scale" in row:
        values = row["position_scale"]["values"]
        if len(values) != 1:
            raise ValueError("invalid position scale component count")
        scale = f32(values[0])
        if scale <= 0:
            raise ValueError("position scale must be positive")
    else:
        missing.append("runtime_position_scale")
    selected = ("0x930", "0x920") if f["0x868"][0] == 0 else ("0x908", "0x8f8")
    scaled_position = tuple(v * scale for v in _axis(f[selected[0]])) if scale is not None else None
    if scaled_position is not None and any(not math.isfinite(v) for v in scaled_position):
        raise ValueError("encoded position overflow")
    position = tuple(math.trunc(v) for v in scaled_position) if scaled_position is not None else (None, None, None)
    if scale is not None and any(not -(2**31) <= v < 2**31 for v in position):
        raise ValueError("encoded position exceeds int32; refusing native indefinite conversion")
    direction = _axis(f["0x1f8"])
    squared = (direction[1] * direction[1] + direction[0] * direction[0]) + direction[2] * direction[2]
    if not math.isfinite(squared):
        raise ValueError("direction magnitude overflow")
    if squared > DIRECTION_THRESHOLD:
        inverse = 1.0 / math.sqrt(squared)
        direction = tuple(v * inverse for v in direction)
    angles = native_angle_components(f[selected[1]])
    primary = {**_float_fields(0x20, direction),
               **{hex(0x2c + 4 * i): v for i, v in enumerate(position)},
               **_float_fields(0x38, (angles[0] * -DEGREES, angles[1] * -DEGREES, angles[2] * DEGREES)),
               "0x44": f["0x8b0"][0], "0x48": f32(f["0x1e0"][2]), "0x8": None}
    b124, b125, b126 = f["0x124"]
    packed = (((((b124 << 4) & 255) | b126) << 3) | b125) & 255
    cache140 = {**_float_fields(8, (*_axis(f["0x128"]), *f["0x140"], f["0x108"][0])), "0x34": packed}
    cache150 = _float_fields(8, (*_axis(f["0x210"]), *_axis(f["0x38"]), *f["0x60"]))
    vector, angles160 = f["0x160"][:3], f["0x160"][3:]
    cache160 = (_float_fields(0x20, (v * scale for v in _axis(vector))) if scale is not None
                else {"0x20": None, "0x24": None, "0x28": None})
    cache160.update(_float_fields(0x2c, (angles160[0] * -DEGREES, angles160[1] * -DEGREES,
                                       angles160[2] * DEGREES)))
    cache170 = None
    if input_sources is None:
        missing.append("preflight_input_sources")
    else:
        cache170 = map_input(input_sources, f["0x8b0"][0])
    if clock is None:
        missing.append("same_domain_native_clock_snapshot")
    else:
        primary["0x8"] = native_timestamp(**clock)
    return {"build": BUILD, "kind": "offline-logical-full-state-v1", "native_apply_ready": False,
            "logical_fields_complete": not missing, "missing": missing,
            "runtime_position_scale": scale,
            "selected_position_field": selected[0], "selected_quaternion_field": selected[1],
            "primary": primary, "cache140": cache140, "cache150": cache150,
            "cache160": cache160, "cache170": cache170,
            "limitations": ["CRT asinf last-bit equivalence unverified", "source capture is not atomic",
                            "not a native object or rollback image", "no cross-host clock mapping"]}


def map_initialization_observation(row):
    """Adapt passive sampler rows, preserving unavailable/clock interval states.

    QPC brackets are observations, not a chosen timestamp for a first packet.
    Missing optional input-chain reads matter only on paths which consume them.
    """
    sources = {}
    for key, item in row["actor_fields"].items():
        offset = int(key, 16)
        stride = 4 if key == "0xfe4" else 1
        for index, value in enumerate(item["values"]):
            sources[hex(offset + stride * index)] = value
    chain = row["input_chain"]
    if chain["status"] == "observed_nonatomic":
        if int(chain["actor+18c8"], 0) == 0:
            sources["mode_object"] = None
        else:
            mode = {"state_108": chain["object+108"]["values"][0], "actor": None}
            if int(chain["object+100"], 0):
                actor = {"flag_b29": chain["target+b29"]["values"][0], "child": None}
                if int(chain["target+b40"], 0):
                    actor["child"] = {"flag_10": chain["leaf+10"]["values"][0]}
                mode["actor"] = actor
            sources["mode_object"] = mode
    result = map_observation(row)
    try:
        result["cache170"] = map_input(sources, result["primary"]["0x44"])
        result["missing"].remove("preflight_input_sources")
    except (KeyError, ValueError) as exc:
        result["input_error"] = str(exc)
    clock = row["clock"]
    if clock["status"] == "observed_nonatomic":
        c08, _c10, c18, c20 = clock["fields_08_10_18_20"]["values"]
        before, after = clock["qpc_before"], clock["qpc_after"]
        if after < before:
            raise ValueError("reversed QPC bracket")
        values = dict(seconds_per_tick=clock["scale"]["values"][0], clock08=c08,
                      clock18=c18, clock20=c20)
        result["native_timestamp_bracket"] = [native_timestamp(qpc_ticks=t, **values) for t in (before, after)]
        result["missing"].remove("same_domain_native_clock_snapshot")
        result["missing"].append("native_clock_point_not_selected")
        result["limitations"].append("clock fields may change within external QPC bracket")
    else:
        result["native_timestamp_bracket"] = None
    result["logical_fields_complete"] = not result["missing"]
    return result
