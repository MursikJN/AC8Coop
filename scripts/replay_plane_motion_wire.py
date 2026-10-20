"""Exercise experimental wire admission with a saved flight. No network/game access."""
import argparse
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import plane_motion_wire as wire


def replay(path):
    raw = path.read_bytes()
    if len(raw) > 16 * 1024 * 1024:
        raise ValueError("capture exceeds replay bound")
    rows = [json.loads(line) for line in raw.splitlines()]
    manifest = json.loads(path.with_suffix(".manifest.json").read_text(encoding="utf-8-sig"))
    if (manifest["result"] != "capture_complete" or manifest["samples"] != len(rows)
            or not 2 <= len(rows) <= 1200 or len({r["index"] for r in rows}) != len(rows)):
        raise ValueError("need complete, bounded capture with unique sample indices")
    # Fixture IDs/nonces only. This is not an actual Steam or native Strix session.
    binding = wire.Binding(1001, 2001, 3001, 1, 1)
    motions = [wire.from_observation(row, binding) for row in rows]
    packets = [wire.encode(m) for m in motions]
    gate = wire.MotionGate(binding)
    before_ready = sum(gate.accept(p, binding.peer_id) is not None for p in packets)
    assert before_ready == 0
    gate.mark_native_ready()
    accepted = [gate.accept(p, binding.peer_id) for p in packets]
    assert all(m is not None for m in accepted)
    error = {field:max(abs(a-b) for x,y in zip(motions,accepted)
                        for a,b in zip(getattr(x,field),getattr(y,field)))
             for field in ("position","orientation","direction")}
    late_duplicates = sum(gate.accept(p, binding.peer_id) is not None for p in packets)
    assert late_duplicates == 0
    gate.retire()
    after_retire = gate.accept(wire.encode(replace(motions[-1], sequence=len(rows)+1,
                                                 source_time_us=motions[-1].source_time_us+100000)), binding.peer_id)
    assert after_retire is None
    stale_checks = {}
    for name in ("peer_nonce", "local_nonce", "mission_epoch", "plane_generation"):
        current = replace(binding, **{name:getattr(binding,name)+1})
        gate = wire.MotionGate(current)
        gate.mark_native_ready()
        leaks = sum(gate.accept(p,binding.peer_id) is not None for p in packets)
        assert leaks == 0
        assert gate.accept(wire.encode(replace(motions[0],binding=current)),binding.peer_id) is not None
        stale_checks[name] = {"old_packets_rejected":len(rows),"fresh_packet_accepted":True}
    impaired = [p for i,p in enumerate(packets) if i % 7 != 0]
    impaired = [p for i in range(0,len(impaired),5) for p in reversed(impaired[i:i+5])]
    gate = wire.MotionGate(binding); gate.mark_native_ready()
    delivered = [m for p in impaired if (m:=gate.accept(p,binding.peer_id)) is not None]
    sequences = [m.sequence for m in delivered]
    assert sequences == sorted(set(sequences))
    return {"status":"offline_replay_passed", "source":str(path),
            "source_sha256":hashlib.sha256(raw).hexdigest(), "samples":len(rows),
            "packet_bytes":wire.SIZE, "total_payload_bytes":sum(map(len,packets)),
            "ordered_accepted":len(accepted), "before_ready_accepted":before_ready,
            "late_duplicate_accepted":late_duplicates,"after_retire_accepted":False,
            "component_roundtrip_max_abs_error":error,"generation_checks":stale_checks,
            "loss_and_reorder_fixture":{"input_packets":len(impaired),"accepted":len(delivered),
                                        "sequences_strictly_increasing":True},
            "limitations":["No Steam packets sent; no game process accessed.",
                           "No native aircraft creation, apply, interpolation, rollback or destruction tested.",
                           "Pose-only research contract; not all fields required by the native consumer.",
                           "MotionGate readiness models a future native adapter; it does not verify native actor health."]}


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args=parser.parse_args()
    report=replay(args.capture)
    with args.output.open("x",encoding="utf-8") as f:
        json.dump(report,f,indent=2);f.write("\n")
    print(json.dumps(report,indent=2))
