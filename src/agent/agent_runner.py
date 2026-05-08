"""Function App agent runner — production-grade.

HTTP trigger que orquestra:
1. Content Safety filter (input)
2. Foundry Agent SDK call (placeholder — refs Story 06.11 agent-code)
3. Content Safety filter (output)
4. Custom App Insights metrics (model, tokens, latency, blocked)
5. Structured logging com tenant_id

Bloqueado se Content Safety detectar conteudo unsafe — emite metric
content_safety_blocked=true e retorna 400.
"""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Any

import azure.functions as func
from azure.ai.contentsafety import ContentSafetyClient
from azure.ai.contentsafety.models import AnalyzeTextOptions, TextCategory
from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.monitor.opentelemetry import configure_azure_monitor

# -----------------------------------------------------------------------------
# Setup OpenTelemetry → App Insights
# -----------------------------------------------------------------------------
APPINSIGHTS_CONNECTION_STRING = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
if APPINSIGHTS_CONNECTION_STRING:
    configure_azure_monitor(connection_string=APPINSIGHTS_CONNECTION_STRING)

logger = logging.getLogger("helpsphere.agent")
logger.setLevel(logging.INFO)

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
CONTENT_SAFETY_ENDPOINT = os.environ.get("CONTENT_SAFETY_ENDPOINT", "")
FOUNDRY_PROJECT_ENDPOINT = os.environ.get("FOUNDRY_PROJECT_ENDPOINT", "")
FOUNDRY_AGENT_ID = os.environ.get("FOUNDRY_AGENT_ID", "")
DEFAULT_MODEL = os.environ.get("DEFAULT_MODEL", "gpt-4.1-mini")

# Threshold: if any category severity >= 4 → BLOCK (severity 0-6 scale)
SAFETY_BLOCK_THRESHOLD = int(os.environ.get("SAFETY_BLOCK_THRESHOLD", "4"))

# -----------------------------------------------------------------------------
# Lazy clients (avoid cold-start cost)
# -----------------------------------------------------------------------------
_credential: DefaultAzureCredential | None = None
_safety_client: ContentSafetyClient | None = None


def _get_credential() -> DefaultAzureCredential:
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential()
    return _credential


def _get_safety_client() -> ContentSafetyClient:
    global _safety_client
    if _safety_client is None:
        if not CONTENT_SAFETY_ENDPOINT:
            raise RuntimeError("CONTENT_SAFETY_ENDPOINT nao configurado")
        _safety_client = ContentSafetyClient(
            endpoint=CONTENT_SAFETY_ENDPOINT,
            credential=_get_credential(),
        )
    return _safety_client


# -----------------------------------------------------------------------------
# Content Safety check
# -----------------------------------------------------------------------------
def check_content_safety(text: str, label: str) -> tuple[bool, dict[str, int]]:
    """Returns (is_safe, severities_per_category)."""
    client = _get_safety_client()
    try:
        response = client.analyze_text(
            AnalyzeTextOptions(
                text=text,
                categories=[
                    TextCategory.HATE,
                    TextCategory.SELF_HARM,
                    TextCategory.SEXUAL,
                    TextCategory.VIOLENCE,
                ],
            )
        )
    except HttpResponseError as exc:
        logger.error("content_safety_call_failed label=%s err=%s", label, exc)
        # Fail closed: trate como unsafe
        return False, {}

    severities = {item.category: item.severity for item in response.categories_analysis}
    is_safe = max(severities.values(), default=0) < SAFETY_BLOCK_THRESHOLD
    return is_safe, severities


# -----------------------------------------------------------------------------
# Foundry Agent call (placeholder — Story 06.11 cravara o real)
# -----------------------------------------------------------------------------
def call_foundry_agent(query: str, tenant_id: str) -> dict[str, Any]:
    """Placeholder — Lab Final D06 (Story 06.11) cravara integracao real
    via azure-ai-projects + agente Foundry com KB grounding.

    Por enquanto retorna mock pra validar pipeline ponta-a-ponta.
    """
    return {
        "answer": f"[STUB] Resposta para tenant {tenant_id}: {query}",
        "model": DEFAULT_MODEL,
        "tokens_input": len(query.split()),
        "tokens_output": 12,
    }


# -----------------------------------------------------------------------------
# HTTP trigger entrypoint
# -----------------------------------------------------------------------------
app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="chat", methods=["POST"])
def chat_completion(req: func.HttpRequest) -> func.HttpResponse:
    start_time = time.time()
    tenant_id = req.headers.get("X-Tenant-Id", "unknown")

    # Parse body
    try:
        body = req.get_json()
        query = body.get("query", "").strip()
        if not query:
            return func.HttpResponse(
                json.dumps({"error": "query field required"}),
                status_code=400,
                mimetype="application/json",
            )
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "invalid JSON body"}),
            status_code=400,
            mimetype="application/json",
        )

    # Content Safety — input filter
    input_safe, input_severities = check_content_safety(query, "input")
    if not input_safe:
        latency_ms = int((time.time() - start_time) * 1000)
        logger.warning(
            "content_safety_blocked_input tenant=%s severities=%s",
            tenant_id,
            input_severities,
        )
        # Custom metric emission
        logger.info(
            "metric_llm_call",
            extra={
                "custom_dimensions": {
                    "model": DEFAULT_MODEL,
                    "tokens_input": 0,
                    "tokens_output": 0,
                    "latency_ms": latency_ms,
                    "content_safety_blocked": True,
                    "blocked_stage": "input",
                    "tenant_id": tenant_id,
                }
            },
        )
        return func.HttpResponse(
            json.dumps({"error": "content safety blocked input", "severities": input_severities}),
            status_code=400,
            mimetype="application/json",
        )

    # Foundry Agent call
    try:
        result = call_foundry_agent(query, tenant_id)
    except Exception as exc:
        logger.exception("foundry_agent_failed tenant=%s err=%s", tenant_id, exc)
        return func.HttpResponse(
            json.dumps({"error": "agent call failed"}),
            status_code=500,
            mimetype="application/json",
        )

    # Content Safety — output filter
    answer = result["answer"]
    output_safe, output_severities = check_content_safety(answer, "output")
    if not output_safe:
        latency_ms = int((time.time() - start_time) * 1000)
        logger.warning(
            "content_safety_blocked_output tenant=%s severities=%s",
            tenant_id,
            output_severities,
        )
        logger.info(
            "metric_llm_call",
            extra={
                "custom_dimensions": {
                    "model": result["model"],
                    "tokens_input": result["tokens_input"],
                    "tokens_output": result["tokens_output"],
                    "latency_ms": latency_ms,
                    "content_safety_blocked": True,
                    "blocked_stage": "output",
                    "tenant_id": tenant_id,
                }
            },
        )
        return func.HttpResponse(
            json.dumps({"error": "content safety blocked output", "severities": output_severities}),
            status_code=502,
            mimetype="application/json",
        )

    # Success — emit metrics
    latency_ms = int((time.time() - start_time) * 1000)
    logger.info(
        "metric_llm_call",
        extra={
            "custom_dimensions": {
                "model": result["model"],
                "tokens_input": result["tokens_input"],
                "tokens_output": result["tokens_output"],
                "latency_ms": latency_ms,
                "content_safety_blocked": False,
                "blocked_stage": None,
                "tenant_id": tenant_id,
            }
        },
    )

    return func.HttpResponse(
        json.dumps(
            {
                "answer": answer,
                "model": result["model"],
                "tokens": {
                    "input": result["tokens_input"],
                    "output": result["tokens_output"],
                },
                "latency_ms": latency_ms,
            }
        ),
        status_code=200,
        mimetype="application/json",
    )
