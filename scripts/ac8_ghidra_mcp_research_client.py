"""Persistent real MCP client for bounded, recorded read-only research batches."""
import asyncio
from datetime import datetime, timezone, timedelta
import json
from pathlib import Path
import tomllib
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

WORKSPACE = Path(__file__).resolve().parent.parent
ROOT = WORKSPACE / ".tools/offline-research"
EVIDENCE = WORKSPACE / "evidence/campaign-coop-ghidra-20261022"
READ_TOOLS = {"get_program_info", "list_functions", "list_classes", "list_namespaces",
              "list_segments", "list_imports", "list_exports", "list_data_items", "list_strings",
              "search_functions_by_name", "get_function_by_address", "decompile_function",
              "decompile_function_by_address", "disassemble_function", "get_xrefs_to", "get_xrefs_from",
              "get_function_xrefs", "get_function_calls", "read_memory"}


def decoded(result):
    if result.isError:
        return None
    if result.structuredContent is not None:
        return result.structuredContent
    for part in result.content:
        if part.type == "text":
            return json.loads(part.text)


async def main():
    cfg = tomllib.loads(Path("C:/Users/Administrator/.codex/config.toml").read_text(encoding="utf-8"))["mcp_servers"]["ghidra-offline"]
    params = StdioServerParameters(command=cfg["command"], args=cfg["args"])
    requests = EVIDENCE / "requests"
    responses = EVIDENCE / "responses"
    requests.mkdir(exist_ok=True)
    responses.mkdir(exist_ok=True)
    with (EVIDENCE / "mcp-server-stderr.log").open("a", encoding="utf-8") as err:
        async with stdio_client(params, errlog=err) as (reader, writer):
            async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=180)) as session:
                init = await session.initialize()
                tools = await session.list_tools()
                (EVIDENCE / "mcp-initialize.json").write_text(json.dumps({"initialize": init.model_dump(mode="json"),
                    "tools": [t.model_dump(mode="json") for t in tools.tools]}, indent=2), encoding="utf-8")
                info = await session.call_tool("get_program_info", {})
                (EVIDENCE / "mcp-program-info.json").write_text(info.model_dump_json(indent=2), encoding="utf-8")
                identity = decoded(info)
                target = json.loads((ROOT / "target.json").read_text(encoding="utf-8"))
                assert identity and identity["sha256"].lower() == target["sha256"], info
                print("GhidraMCP ready; target identity verified", flush=True)
                available = {t.name for t in tools.tools}
                while True:
                    if (requests / "STOP").exists():
                        break
                    for job in sorted(requests.glob("*.json")):
                        output = responses / job.name
                        if output.exists():
                            continue
                        query = json.loads(job.read_text(encoding="utf-8"))
                        tool = query["tool"]
                        if tool not in READ_TOOLS or tool not in available:
                            raise ValueError(f"Unapproved/unavailable research tool: {tool}")
                        result = await session.call_tool(tool, query.get("arguments", {}))
                        record = {"time_utc": datetime.now(timezone.utc).isoformat(), "image_sha256": target["sha256"],
                                  "query": query, "response": result.model_dump(mode="json"), "data": decoded(result)}
                        temporary = output.with_suffix(".partial")
                        temporary.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
                        temporary.replace(output)
                        print(job.name, tool, "ERROR" if result.isError else "ok", flush=True)
                    await asyncio.sleep(0.5)
                print("Research batches completed; closing Ghidra project", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
