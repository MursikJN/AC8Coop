"""Prepare a bounded Ghidra database from the pinned offline AC8 copy; never execute it."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import sys

WORKSPACE = Path(__file__).resolve().parent.parent
ROOT = WORKSPACE / ".tools/offline-research"
EVIDENCE = WORKSPACE / "evidence/campaign-coop-ghidra-20261022"


def main():
    target = json.loads((ROOT / "target.json").read_text(encoding="utf-8"))
    binary = Path(target["binary"]).resolve(strict=True)
    if not binary.is_relative_to(ROOT / "targets"):
        raise ValueError("Only pinned offline target copies are allowed")
    with binary.open("rb") as f:
        assert hashlib.file_digest(f, "sha256").hexdigest() == target["sha256"]
    ghidra = next((ROOT / "ghidra").glob("ghidra_*_PUBLIC"))
    jdk = next((ROOT / "jdk").glob("jdk-*"))
    os.environ["JAVA_HOME"] = str(jdk)
    ipc = WORKSPACE / "build/java-ipc"
    ipc.mkdir(parents=True, exist_ok=True)
    os.environ["JAVA_TOOL_OPTIONS"] = f'-Djdk.net.unixdomain.tmpdir="{ipc}"'
    from pyghidra.launcher import HeadlessPyGhidraLauncher
    launcher = HeadlessPyGhidraLauncher(install_dir=ghidra)
    launcher.add_vmargs("-Xmx1200m")
    launcher.start()
    import pyghidra
    from ghidra.program.flatapi import FlatProgramAPI
    from ghidra.util.task import TaskMonitor
    from jpype.types import JLong
    project_dir = Path(target["project"]).resolve()
    if not project_dir.is_relative_to(WORKSPACE / "build/offline-ghidra-projects"):
        raise ValueError("Project outside allowed research directory")
    project_dir.mkdir(parents=True, exist_ok=True)
    project = pyghidra.open_project(str(project_dir), target["project_name"], create=True)
    monitor = TaskMonitor.DUMMY
    if project.getProjectData().getFile("/" + binary.name) is None:
        print("Importing offline PE without global auto-analysis", flush=True)
        results = pyghidra.program_loader().project(project).source(str(binary)).name(binary.name).load()
        try:
            results.getPrimary().save(monitor)
        finally:
            results.close()
    program, consumer = pyghidra.consume_program(project, "/" + binary.name)
    print("Imported program; preparing targeted database functions", flush=True)
    assert str(program.getExecutableSHA256()).lower() == target["sha256"]
    seed = json.loads((EVIDENCE / "ghidra-seed.json").read_text(encoding="utf-8"))
    api = FlatProgramAPI(program)
    base = int(str(program.getImageBase()), 16)
    tx = program.startTransaction("Offline candidate preparation, no semantic renaming")
    report = {"time_utc": datetime.now(timezone.utc).isoformat(), "image_sha256": target["sha256"],
              "image_base": hex(base), "global_auto_analysis": False, "functions": [], "strings": []}
    committed = False
    try:
        for entry in seed["strings"]:
            address = api.toAddr(JLong(base + entry["rva"]))
            try:
                if entry["encoding"] == "utf-16-le":
                    api.createUnicodeString(address)
                else:
                    api.createAsciiString(address)
                report["strings"].append({"rva": hex(entry["rva"]), "status": "defined_from_file_bytes"})
            except Exception as e:
                report["strings"].append({"rva": hex(entry["rva"]), "status": "not_defined", "reason": str(e)[:300]})
        for entry in seed["functions"]:
            rv = int(entry["rva"], 0)
            address = api.toAddr(JLong(base + rv))
            try:
                disassembled = api.disassemble(address)
                function = program.getFunctionManager().getFunctionAt(address)
                if function is None:
                    function = api.createFunction(address, None)
                report["functions"].append({"rva": hex(rv), "disassembled": bool(disassembled),
                    "name": str(function.getName()) if function else None,
                    "body_addresses": int(function.getBody().getNumAddresses()) if function else 0,
                    "sources": entry["sources"]})
            except Exception as e:
                report["functions"].append({"rva": hex(rv), "error": str(e)[:500], "sources": entry["sources"]})
        committed = True
    finally:
        program.endTransaction(tx, committed)
        if committed:
            program.save("Focused offline research preparation", monitor)
        program.release(consumer)
        project.close()
    (EVIDENCE / "ghidra-preparation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Saved {len(report['functions'])} candidate function preparations; no semantic labels assigned", flush=True)


if __name__ == "__main__":
    try:
        main()
    except BaseException:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(1)
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
