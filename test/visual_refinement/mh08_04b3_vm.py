"""Read-only VM Service counters for the running MH08 preview."""
from __future__ import annotations
import argparse
import json
import re
import tempfile
import urllib.request
from pathlib import Path
from urllib.parse import urlencode, urlparse
ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = (ROOT / "docs/features/mh08/artifacts/visual_04b3").resolve()
VM_LOG = Path(tempfile.gettempdir()) / "mh08_04b3_flutter_run.log"
URL_RE = re.compile(r"(?:https?|ws)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/\S+")
class Unavailable(RuntimeError):
    pass
def service_url():
    try:
        text = VM_LOG.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        raise Unavailable("VM service log is unavailable") from error
    lines = [x for x in text.splitlines() if "Dart VM Service" in x and "available at:" in x]
    match = URL_RE.search(lines[-1]) if lines else None
    if not match:
        raise Unavailable("VM service URL is unavailable in the local log")
    url = match.group(0).rstrip("),.")
    if url.startswith("ws://"):
        url = "http://" + url[5:]
    if urlparse(url).hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise Unavailable("VM service endpoint is not loopback")
    return url
class Rpc:
    def __init__(self, url):
        self.url = url
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def call(self, method, params=None):
        query = urlencode(params or {})
        target = self.url.rstrip("/") + "/" + method + ("?" + query if query else "")
        try:
            with self.opener.open(target, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except Exception as error:
            raise Unavailable(f"VM service request failed: {method}") from error
        if "error" in payload or "result" not in payload:
            error = payload.get("error", {})
            raise Unavailable(f"VM service RPC failed: {method} ({error.get('code')}: {error.get('message')})")
        return payload["result"]
def fields(rpc, isolate_id, object_id):
    obj = rpc.call("getObject", {"isolateId": isolate_id, "objectId": object_id})
    return {item.get("name"): item.get("value", {}) for item in obj.get("fields", []) if item.get("name")}
def scalar(value):
    if not isinstance(value, dict) or value.get("kind") == "Null":
        return None
    return value.get("valueAsString")
def required(mapping, name):
    value = mapping.get(name)
    if not isinstance(value, dict) or not value.get("id"):
        raise Unavailable(f"VM object field is unavailable: {name}")
    return value
def integer(value, name):
    try:
        return int(scalar(value))
    except (TypeError, ValueError) as error:
        raise Unavailable(f"VM integer field is unavailable: {name}") from error
def list_values(rpc, isolate_id, object_id):
    obj = rpc.call("getObject", {"isolateId": isolate_id, "objectId": object_id})
    length, elements = obj.get("length"), obj.get("elements") or []
    if length is None or int(length) != len(elements):
        raise Unavailable("VM list elements are incomplete")
    return elements
def query_data(rpc, isolate_id, query_id):
    query = fields(rpc, isolate_id, query_id)
    search = scalar(required(query, "search"))
    cursor = scalar(required(query, "cursor"))
    statuses_ref = required(query, "statuses")
    statuses = []
    for item in list_values(rpc, isolate_id, statuses_ref["id"]):
        status = fields(rpc, isolate_id, required({"status": item}, "status")["id"])
        status_name = scalar(status.get("_name") or status.get("name"))
        if status_name is None:
            raise Unavailable("VM status enum name is unavailable")
        statuses.append(status_name)
    return search, cursor, statuses
def environment_data(rpc, isolate_id, object_id):
    env = fields(rpc, isolate_id, object_id)
    scenario_ref = required(env, "scenario")
    scenario_fields = fields(rpc, isolate_id, scenario_ref["id"])
    scenario = scalar(scenario_fields.get("_name") or scenario_fields.get("name"))
    if scalar(env.get("screen")) is None or scenario is None:
        raise Unavailable("VM environment fields are unavailable")
    return {"id": object_id, "screen": scalar(env["screen"]), "scenario": scenario, "generation": integer(required(env, "generation"), "generation"), "orders": required(env, "orders")["id"]}
def read_snapshot(phase):
    rpc = Rpc(service_url())
    vm = rpc.call("getVM")
    isolates = vm.get("isolates") or []
    isolates = isolates.get("isolates") if isinstance(isolates, dict) else isolates
    isolate = next((x for x in isolates if x.get("name") == "main"), None)
    if not isolate or not isolate.get("id"):
        raise Unavailable("main isolate is unavailable")
    isolate_id = isolate["id"]
    classes = rpc.call("getClassList", {"isolateId": isolate_id}).get("classes") or []
    klass = next((x for x in classes if x.get("name") == "Mh08PreviewEnvironment"), None)
    if not klass or not klass.get("id"):
        raise Unavailable("Mh08PreviewEnvironment class is unavailable")
    instances = rpc.call("getInstances", {"isolateId": isolate_id, "objectId": klass["id"], "limit": 5}).get("instances") or []
    candidates = [environment_data(rpc, isolate_id, x["id"]) for x in instances if x.get("id")]
    if not candidates:
        raise Unavailable("Mh08PreviewEnvironment instance is unavailable")
    highest = max(item["generation"] for item in candidates)
    active = [item for item in candidates if item["generation"] == highest]
    if len(active) != 1:
        summary = [{k: item[k] for k in ("screen", "scenario", "generation")} for item in active]
        raise Unavailable("ambiguous environment candidates: " + json.dumps(summary, separators=(",", ":")))
    env = active[0]
    repo = fields(rpc, isolate_id, env["orders"])
    manager = fields(rpc, isolate_id, required(repo, "manager")["id"])
    reads = list_values(rpc, isolate_id, required(manager, "_managerReads")["id"])
    detail_reads = list_values(rpc, isolate_id, required(manager, "_managerDetailReads")["id"])
    queries = [query_data(rpc, isolate_id, item["id"]) for item in reads]
    head = sum(cursor is None for _, cursor, _ in queries)
    latest = queries[-1] if queries else (None, None, [])
    return {"status": "ok", "phase": phase, "environment": {k: env[k] for k in ("screen", "scenario", "generation")}, "reads": {"manager": len(queries), "head": head, "cursor": len(queries) - head, "details": len(detail_reads), "cursorHistory": "|".join("<head>" if q[1] is None else q[1] for q in queries)}, "latestQuery": {"search": latest[0], "statusNames": latest[2]}, "instanceLimit": 5}
def output_path(raw):
    path = (ROOT / raw if not Path(raw).is_absolute() else Path(raw)).resolve()
    if OUT_ROOT not in path.parents:
        raise ValueError("--output must remain in the MH08 04B3 artifact directory")
    if path.exists():
        raise FileExistsError("Refusing to overwrite existing output")
    if not path.parent.is_dir():
        raise FileNotFoundError("Output directory is unavailable")
    return path
def main():
    parser = argparse.ArgumentParser(description="Read-only MH08 VM counters")
    parser.add_argument("--phase", default="snapshot")
    parser.add_argument("--output")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.phase):
        parser.error("--phase must be simple ASCII")
    destination = output_path(args.output) if args.output else None
    try:
        result = read_snapshot(args.phase)
    except Unavailable as error:
        result = {"status": "unavailable", "phase": args.phase, "limitation": str(error)}
    except (KeyError, AttributeError, TypeError, ValueError):
        result = {"status": "unavailable", "phase": args.phase, "limitation": "VM service response schema is unavailable"}
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    print(text, end="")
    if destination:
        destination.write_text(text, encoding="utf-8")
if __name__ == "__main__":
    main()
