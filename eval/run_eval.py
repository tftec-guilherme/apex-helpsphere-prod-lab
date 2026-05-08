"""Offline evaluation harness — Lab Avancado D06.

Carrega dataset.jsonl, chama agent endpoint via Function App / APIM gateway,
mede groundedness (embedding similarity), relevance (gpt-4.1-mini judge),
latency. Output: report.json + summary table stdout.

Usage:
    python eval/run_eval.py --endpoint https://apim-helpsphere-XXXX.azure-api.net/agent/chat \
        --subscription-key YOUR_APIM_KEY \
        --dataset eval/dataset.jsonl \
        --output eval/report.json
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from pathlib import Path
from typing import Any

import requests


# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
DEFAULT_TIMEOUT_S = 30
JUDGE_MODEL = "gpt-4.1-mini"


# -----------------------------------------------------------------------------
# Dataset loader
# -----------------------------------------------------------------------------
def load_dataset(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


# -----------------------------------------------------------------------------
# Agent caller
# -----------------------------------------------------------------------------
def call_agent(
    endpoint: str,
    query: str,
    subscription_key: str,
    tenant_id: str = "eval-tenant",
) -> tuple[dict[str, Any], int, float]:
    headers = {
        "Content-Type": "application/json",
        "Ocp-Apim-Subscription-Key": subscription_key,
        "X-Tenant-Id": tenant_id,
    }
    body = {"query": query}
    start = time.time()
    try:
        resp = requests.post(endpoint, json=body, headers=headers, timeout=DEFAULT_TIMEOUT_S)
        latency_ms = int((time.time() - start) * 1000)
        return resp.json() if resp.headers.get("content-type", "").startswith(
            "application/json"
        ) else {"raw": resp.text}, resp.status_code, latency_ms
    except requests.exceptions.RequestException as exc:
        latency_ms = int((time.time() - start) * 1000)
        return {"error": str(exc)}, 0, latency_ms


# -----------------------------------------------------------------------------
# Groundedness via embedding similarity (placeholder — Bloco C cravara real)
# -----------------------------------------------------------------------------
def score_groundedness(query: str, answer: str) -> float:
    """Placeholder — Bloco C cravara via azure-ai-projects embeddings + cosine.

    Por enquanto retorna heuristic baseada em len(answer) > 0 e nao-stub.
    """
    if not answer or "[STUB]" in answer:
        return 0.0
    # Heuristic provisorio: 0.5 baseline + bonus pra non-stub responses
    return 0.5


# -----------------------------------------------------------------------------
# Relevance via LLM judge (placeholder — Bloco C cravara real)
# -----------------------------------------------------------------------------
def score_relevance(query: str, answer: str, expected_intent: str) -> float:
    """Placeholder — Bloco C cravara via gpt-4.1-mini judge prompt.

    Por enquanto retorna 0.5 sempre (neutral).
    """
    return 0.5


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description="Run offline eval against agent endpoint")
    parser.add_argument("--endpoint", required=True, help="APIM gateway URL (.../agent/chat)")
    parser.add_argument(
        "--subscription-key",
        default=os.environ.get("APIM_SUBSCRIPTION_KEY", ""),
        help="APIM subscription key (or set APIM_SUBSCRIPTION_KEY env)",
    )
    parser.add_argument("--dataset", default="eval/dataset.jsonl", help="Path to dataset.jsonl")
    parser.add_argument("--output", default="eval/report.json", help="Path to output report")
    parser.add_argument("--tenant-id", default="eval-tenant", help="Tenant ID header")
    args = parser.parse_args()

    if not args.subscription_key:
        print("ERROR: --subscription-key required (or set APIM_SUBSCRIPTION_KEY env)", file=sys.stderr)
        return 2

    dataset = load_dataset(Path(args.dataset))
    print(f"Loaded {len(dataset)} scenarios from {args.dataset}")

    results: list[dict[str, Any]] = []
    for case in dataset:
        case_id = case["id"]
        query = case["query"]
        expected_intent = case.get("expected_intent", "")
        print(f"\n[{case_id}] Query: {query}")

        response, status_code, latency_ms = call_agent(
            args.endpoint, query, args.subscription_key, args.tenant_id
        )
        print(f"  HTTP {status_code} | {latency_ms}ms")

        answer = response.get("answer", "")
        groundedness = score_groundedness(query, answer)
        relevance = score_relevance(query, answer, expected_intent)

        results.append(
            {
                "id": case_id,
                "query": query,
                "expected_intent": expected_intent,
                "status_code": status_code,
                "latency_ms": latency_ms,
                "answer": answer,
                "groundedness": groundedness,
                "relevance": relevance,
                "expected_safety_block": case.get("expected_safety_block", False),
                "actual_safety_block": status_code in (400, 502)
                and "content safety" in str(response.get("error", "")).lower(),
            }
        )

    # Aggregate
    successful = [r for r in results if r["status_code"] == 200]
    blocked = [r for r in results if r["actual_safety_block"]]

    summary = {
        "total": len(results),
        "successful": len(successful),
        "safety_blocked": len(blocked),
        "errors": len(results) - len(successful) - len(blocked),
        "latency_ms": {
            "p50": statistics.median([r["latency_ms"] for r in successful]) if successful else 0,
            "avg": statistics.mean([r["latency_ms"] for r in successful]) if successful else 0,
            "max": max([r["latency_ms"] for r in successful]) if successful else 0,
        },
        "groundedness_avg": statistics.mean([r["groundedness"] for r in successful])
        if successful
        else 0,
        "relevance_avg": statistics.mean([r["relevance"] for r in successful]) if successful else 0,
    }

    output = {"summary": summary, "results": results}
    Path(args.output).write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(json.dumps(summary, indent=2))
    print(f"\nFull report: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
