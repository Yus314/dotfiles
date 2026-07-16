#!/usr/bin/env python3
"""MCP server exposing Parallel, Exa, and Firecrawl research APIs.

Secrets are loaded from environment variables first, then from the user's
sops-nix decrypted Hermes gateway env file. Values are never returned.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Literal

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("research-providers")

DEFAULT_ENV_FILES = [
    Path(os.environ.get("HERMES_RESEARCH_ENV_FILE", "")) if os.environ.get("HERMES_RESEARCH_ENV_FILE") else None,
    Path.home() / ".config/sops-nix/secrets/hermes-gateway-env",
    Path.home() / ".hermes/.env",
]


def _load_dotenv_keys() -> dict[str, str]:
    values: dict[str, str] = {}
    for p in DEFAULT_ENV_FILES:
        if not p or not p.exists():
            continue
        try:
            for line in p.read_text(errors="replace").splitlines():
                s = line.strip()
                if not s or s.startswith("#") or "=" not in s:
                    continue
                k, v = s.split("=", 1)
                v = v.strip().strip('"').strip("'")
                values.setdefault(k.strip(), v)
        except OSError:
            continue
    return values


def _key(name: str) -> str:
    val = os.environ.get(name) or _load_dotenv_keys().get(name)
    if not val:
        raise RuntimeError(f"Missing required API key: {name}")
    return val


def _request(method: str, url: str, headers: dict[str, str] | None = None, body: Any | None = None, timeout: int = 60) -> dict[str, Any]:
    headers = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers.setdefault("Content-Type", "application/json")
    started = time.time()
    try:
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8", "replace")
            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                payload = {"text": text[:5000]}
            return {"ok": True, "status": resp.status, "elapsed_s": round(time.time() - started, 3), "data": payload}
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", "replace")[:2000]
        return {"ok": False, "status": e.code, "elapsed_s": round(time.time() - started, 3), "error": err}
    except Exception as e:  # keep MCP tool failures structured
        return {"ok": False, "status": None, "elapsed_s": round(time.time() - started, 3), "error": repr(e)}


def _truncate_text(value: Any, max_chars: int) -> Any:
    if isinstance(value, str):
        return value if len(value) <= max_chars else value[:max_chars] + f"\n...[truncated {len(value) - max_chars} chars]"
    if isinstance(value, list):
        return [_truncate_text(v, max_chars) for v in value]
    if isinstance(value, dict):
        return {k: _truncate_text(v, max_chars) for k, v in value.items()}
    return value


@mcp.tool()
def research_search(
    provider: Literal["parallel", "exa", "firecrawl"],
    query: str,
    objective: str = "",
    max_results: int = 5,
    include_content: bool = False,
) -> dict[str, Any]:
    """Search with Parallel, Exa, or Firecrawl.

    provider: one of parallel, exa, firecrawl.
    query: user/search query.
    objective: optional Parallel objective to focus results.
    max_results: 1-10 recommended.
    include_content: for Firecrawl, scrape markdown for returned results; for Exa, include highlights.
    """
    max_results = max(1, min(int(max_results), 10))
    if provider == "parallel":
        queries = [q.strip() for q in query.split(";") if q.strip()] or [query]
        body = {
            "search_queries": queries[:3],
            "objective": objective or query,
            "mode": "basic",
            "max_chars_total": 4000 if include_content else 1500,
        }
        res = _request("POST", "https://api.parallel.ai/v1/search", {"x-api-key": _key("PARALLEL_API_KEY")}, body)
        if res["ok"]:
            results = (res["data"].get("results") or [])[:max_results]
            return {"ok": True, "provider": provider, "elapsed_s": res["elapsed_s"], "search_id": res["data"].get("search_id"), "session_id": res["data"].get("session_id"), "results": results}
        return {"ok": False, "provider": provider, **{k: res[k] for k in ("status", "elapsed_s", "error")}}

    if provider == "exa":
        body: dict[str, Any] = {"query": query, "type": "auto", "numResults": max_results}
        if include_content:
            body["contents"] = {"highlights": {"numSentences": 2}}
        res = _request("POST", "https://api.exa.ai/search", {"x-api-key": _key("EXA_API_KEY")}, body)
        if res["ok"]:
            return {"ok": True, "provider": provider, "elapsed_s": res["elapsed_s"], "request_id": res["data"].get("requestId"), "results": (res["data"].get("results") or [])[:max_results]}
        return {"ok": False, "provider": provider, **{k: res[k] for k in ("status", "elapsed_s", "error")}}

    if provider == "firecrawl":
        body = {"query": query, "limit": max_results, "sources": ["web"], "timeout": 45000}
        if include_content:
            body["scrapeOptions"] = {"formats": ["markdown"], "onlyMainContent": True, "maxAge": 172800000}
        res = _request("POST", "https://api.firecrawl.dev/v2/search", {"Authorization": "Bearer " + _key("FIRECRAWL_API_KEY")}, body, timeout=60)
        if res["ok"]:
            data = res["data"].get("data") or {}
            web = data.get("web") if isinstance(data, dict) else []
            return {"ok": True, "provider": provider, "elapsed_s": res["elapsed_s"], "success": res["data"].get("success"), "results": (web or [])[:max_results]}
        return {"ok": False, "provider": provider, **{k: res[k] for k in ("status", "elapsed_s", "error")}}

    raise ValueError(f"Unsupported provider: {provider}")


@mcp.tool()
def research_extract(
    provider: Literal["parallel", "exa", "firecrawl"],
    url: str,
    objective: str = "Extract the main relevant content.",
    max_chars: int = 6000,
) -> dict[str, Any]:
    """Extract/read one URL with Parallel, Exa, or Firecrawl."""
    max_chars = max(1000, min(int(max_chars), 30000))
    if provider == "parallel":
        body = {
            "urls": [url],
            "objective": objective,
            "max_chars_total": max_chars,
            "advanced_settings": {"full_content": {"enabled": True}},
        }
        res = _request("POST", "https://api.parallel.ai/v1/extract", {"x-api-key": _key("PARALLEL_API_KEY")}, body)
        if res["ok"]:
            return {"ok": True, "provider": provider, "elapsed_s": res["elapsed_s"], "extract_id": res["data"].get("extract_id"), "results": _truncate_text(res["data"].get("results") or [], max_chars), "errors": res["data"].get("errors") or []}
        return {"ok": False, "provider": provider, **{k: res[k] for k in ("status", "elapsed_s", "error")}}

    if provider == "exa":
        body = {"urls": [url], "text": {"maxCharacters": max_chars}, "summary": {"query": objective}}
        res = _request("POST", "https://api.exa.ai/contents", {"x-api-key": _key("EXA_API_KEY")}, body)
        if res["ok"]:
            return {"ok": True, "provider": provider, "elapsed_s": res["elapsed_s"], "request_id": res["data"].get("requestId"), "results": _truncate_text(res["data"].get("results") or [], max_chars), "statuses": res["data"].get("statuses")}
        return {"ok": False, "provider": provider, **{k: res[k] for k in ("status", "elapsed_s", "error")}}

    if provider == "firecrawl":
        body = {"url": url, "formats": ["markdown"], "onlyMainContent": True, "timeout": 45000, "maxAge": 172800000}
        res = _request("POST", "https://api.firecrawl.dev/v2/scrape", {"Authorization": "Bearer " + _key("FIRECRAWL_API_KEY")}, body)
        if res["ok"]:
            data = res["data"].get("data") or {}
            return {"ok": True, "provider": provider, "elapsed_s": res["elapsed_s"], "success": res["data"].get("success"), "data": _truncate_text(data, max_chars)}
        return {"ok": False, "provider": provider, **{k: res[k] for k in ("status", "elapsed_s", "error")}}

    raise ValueError(f"Unsupported provider: {provider}")


@mcp.tool()
def parallel_research_task(input: str, processor: Literal["base", "core", "pro"] = "base", wait_timeout_s: int = 120) -> dict[str, Any]:
    """Run a Parallel Task API research task and wait for its result.

    Use for small cited research tasks where a JSON/text answer with basis sources is useful.
    """
    body = {"input": input, "processor": processor}
    created = _request("POST", "https://api.parallel.ai/v1/tasks/runs", {"x-api-key": _key("PARALLEL_API_KEY")}, body, timeout=30)
    if not created["ok"]:
        return {"ok": False, "provider": "parallel", "phase": "create", **{k: created[k] for k in ("status", "elapsed_s", "error")}}
    run_id = created["data"].get("run_id") or (created["data"].get("run") or {}).get("run_id")
    if not run_id:
        return {"ok": False, "provider": "parallel", "phase": "create", "error": "No run_id in response", "response": created["data"]}
    result = _request("GET", f"https://api.parallel.ai/v1/tasks/runs/{run_id}/result", {"x-api-key": _key("PARALLEL_API_KEY")}, None, timeout=max(30, min(int(wait_timeout_s), 300)))
    if result["ok"]:
        return {"ok": True, "provider": "parallel", "run_id": run_id, "elapsed_s": created["elapsed_s"] + result["elapsed_s"], "result": result["data"]}
    return {"ok": False, "provider": "parallel", "run_id": run_id, "phase": "result", **{k: result[k] for k in ("status", "elapsed_s", "error")}}


if __name__ == "__main__":
    mcp.run()
