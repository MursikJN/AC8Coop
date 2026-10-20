"""Passive initial-state source capture. VM_READ only, no injected calls or writes.

Adds previously missing pre-flight input sources, world pose companion and native
clock observations. This is NOT a ready-to-apply native snapshot or spawn test.
"""
import argparse
import ctypes
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import struct
import time
import sample_plane_motion as motion

ACTOR_FIELDS = {
    "0x6c8": "f", "0xfe4": "6f", "0xffc": "B", "0x1313": "3B",
    "0x13d1": "B", "0x58dc": "B", "0xed8": "B", "0x3c38": "q",
}
CLOCK_POINTER_RVA = 0xE525F90
CLOCK_SCALE_RVA = 0xE3FAD40
POSITION_SCALE_RVA = 0xDC4C03C


def numeric(values):
    return [v if not isinstance(v, float) or math.isfinite(v) else str(v) for v in values]


class InitializationReader(motion.FlightReader):
    def __init__(self, read, base, ticket, qpc):
        super().__init__(read, base, ticket)
        self.qpc = qpc

    def block(self, address, fmt):
        raw = self.read(address, struct.calcsize("<" + fmt))
        return {"values": numeric(struct.unpack("<" + fmt, raw)), "raw_hex": raw.hex()}

    def chain(self):
        # Bounded observation of the input-bit predicate's optional chain.
        # These are raw pointer checks, NOT an engine weak-object serial proof.
        pawn = self.ticket["pawn"]
        edges, blocks, result = [], [], {}
        def edge(address):
            pointer = self.qword(address)
            edges.append((address, pointer))
            if pointer and (pointer % 8 or not 0x10000 <= pointer < 0x800000000000):
                raise ValueError("invalid input-chain pointer")
            return pointer
        def read_field(name, pointer, offset, fmt):
            result[name] = self.block(pointer + offset, fmt)
        a = edge(pawn + 0x18c8)
        result["actor+18c8"] = hex(a)
        if a:
            blocks.append((a, self.read(a, 0x28)))
            read_field("object+108", a, 0x108, "B")
            b = edge(a + 0x100)
            result["object+100"] = hex(b)
            if b:
                blocks.append((b, self.read(b, 0x28)))
                read_field("target+b29", b, 0xb29, "B")
                c = edge(b + 0xb40)
                result["target+b40"] = hex(c)
                if c: read_field("leaf+10", c, 0x10, "B")
        for address, old in edges:
            if self.qword(address) != old: raise ValueError("input-chain pointer changed")
        for address, old in blocks:
            if self.read(address, 0x28) != old: raise ValueError("input-chain header changed")
        result["status"] = "observed_nonatomic"
        return result

    def clock(self):
        before = self.qpc()
        pointer = self.qword(self.base + CLOCK_POINTER_RVA)
        scale = self.block(self.base + CLOCK_SCALE_RVA, "d")
        result = {"pointer": hex(pointer), "scale": scale, "qpc_before": before}
        if pointer:
            if pointer % 8 or not 0x10000 <= pointer < 0x800000000000:
                raise ValueError("invalid clock pointer")
            result["fields_08_10_18_20"] = self.block(pointer + 8, "4q")
        if self.qword(self.base + CLOCK_POINTER_RVA) != pointer:
            raise ValueError("clock instance changed")
        result.update(qpc_after=self.qpc(), status="observed_nonatomic" if pointer else "not_initialized")
        return result

    def sample(self, layout):
        self.check_identity()
        scale = self.block(self.base + POSITION_SCALE_RVA, "f")
        value = scale["values"][0]
        if type(value) is not float or not math.isfinite(value) or value <= 0:
            raise ValueError("invalid runtime position scale")
        fields = motion.decode_block(self.read(self.ticket["pawn"] + motion.INLINE, motion.EXTENT), layout)
        actor = {key: self.block(self.ticket["pawn"] + int(key, 0), fmt) for key, fmt in ACTOR_FIELDS.items()}
        # Failure to inspect an optional chain does not invent zero input flags.
        try: chain = self.chain()
        except (OSError, ValueError) as error: chain = {"status": "unavailable", "error": str(error)}
        clock = self.clock()
        if self.block(self.base + POSITION_SCALE_RVA, "f") != scale:
            raise ValueError("runtime position scale changed during read")
        self.check_identity()
        return {"fields": fields, "actor_fields": actor, "input_chain": chain, "clock": clock,
                "position_scale": scale}


def read_pose(path, ticket):
    if path.stat().st_size > 4096: raise ValueError("pose file too large")
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    values = dict(line.split("\t", 1) for line in lines)
    expected = {"pawn", "world", "location_x", "location_y", "location_z", "rotation_pitch", "rotation_yaw", "rotation_roll"}
    if len(lines) != 8 or values.keys() != expected: raise ValueError("invalid pose schema")
    if any(int(values[k], 0) != ticket[k] for k in ("pawn", "world")): raise ValueError("pose owner mismatch")
    for k in expected - {"pawn", "world"}:
        values[k] = float(values[k])
        if not math.isfinite(values[k]): raise ValueError("nonfinite reflected pose")
    return values


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--session", type=Path, required=True)
    p.add_argument("--wait-ticket", type=int, default=900)
    p.add_argument("--duration", type=float, default=30)
    p.add_argument("--hz", type=float, default=10)
    a = p.parse_args()
    if not 0 < a.duration <= 60 or not 1 <= a.hz <= 20 or not 0 <= a.wait_ticket <= 900:
        p.error("invalid bounded capture settings")
    session = json.loads((a.session / "session.json").read_text(encoding="utf-8-sig"))
    if (session["extension"] != "plane_initialization_probe.lua" or session["game_sha256"].lower() != motion.SHA
            or session.get("finished")):
        raise ValueError("need active initialization probe session")
    started = datetime.fromisoformat(session["started"]).timestamp()
    reader = motion.WindowsReader(int(session["pid"]), started)
    layout = motion.load_layout()
    try:
        qpc_fn = reader.k.QueryPerformanceCounter
        qpc_fn.argtypes = [ctypes.POINTER(ctypes.c_longlong)]
        qpc_fn.restype = ctypes.c_int
        def qpc():
            value = ctypes.c_longlong()
            if not qpc_fn(ctypes.byref(value)): raise OSError("QPC unavailable")
            return value.value
        deadline = time.monotonic() + a.wait_ticket
        print("WAITING_FOR_INITIALIZATION_F8_TICKET", flush=True)
        while True:
            paths = sorted(a.session.glob("initialization-ticket-*.tsv"), key=lambda f: f.stat().st_mtime_ns, reverse=True)
            if paths:
                ticket_path = paths[0]
                ticket = motion.parse_ticket(ticket_path, reader.created, started, time.time())
                break
            if time.monotonic() >= deadline: raise TimeoutError("no fresh F8 ticket")
            time.sleep(.2)
        suffix = ticket_path.stem.removeprefix("initialization-ticket-")
        pose = read_pose(a.session / ("initialization-pose-" + suffix + ".tsv"), ticket)
        probe = InitializationReader(reader.read, reader.base, ticket, qpc)
        output = a.session / ("initialization-sources-" + suffix + ".jsonl")
        manifest_path = output.with_suffix(".manifest.json")
        manifest = dict(result="recording", read_only=True, samples=0, pid=session["pid"], ticket=ticket,
                        game_sha256=motion.SHA, base=hex(reader.base), reflected_pose=pose,
                        limitations="Nonatomic external observations; pose getter precedes sampling. Pause baseline required. No lifetime pin, native apply, creation, cleanup or clock synchronization tested.")
        with manifest_path.open("x", encoding="utf-8") as f: json.dump(manifest, f, indent=2)
        try:
            with output.open("x", encoding="utf-8") as f:
                print("RECORDING_INITIALIZATION_SOURCES_READ_ONLY", flush=True)
                begin = time.perf_counter()
                for i in range(math.ceil(a.duration * a.hz)):
                    remaining = begin + i / a.hz - time.perf_counter()
                    if remaining > 0: time.sleep(remaining)
                    sample_started = time.perf_counter()
                    row = probe.sample(layout)
                    row.update(index=i, elapsed_s=sample_started - begin, read_ms=(time.perf_counter()-sample_started)*1000)
                    f.write(json.dumps(row, allow_nan=False)+"\n"); f.flush()
                    manifest["samples"] += 1
                manifest["result"] = "capture_complete"
        except Exception as error:
            manifest.update(result="stopped", error=str(error))
        finally:
            manifest["finished"] = datetime.now().astimezone().isoformat()
            if output.exists(): manifest["capture_sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
            temp = manifest_path.with_suffix(".tmp")
            temp.write_text(json.dumps(manifest, indent=2, allow_nan=False)+"\n", encoding="utf-8")
            temp.replace(manifest_path)
        print(json.dumps(dict(result=manifest["result"], samples=manifest["samples"], output=str(output))), flush=True)
        if manifest["result"] != "capture_complete": raise SystemExit(1)
    finally: reader.close()


if __name__ == "__main__": main()
