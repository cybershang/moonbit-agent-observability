# Agent Observability with GreptimeDB

A lightweight, GreptimeDB-backed observability stack for GenAI agents.
It replaces separate trace/metric/log stores (Jaeger/Prometheus/Loki) with a
single GreptimeDB instance and a pre-built Grafana dashboard.

## Conventions

This stack uses the latest OpenTelemetry GenAI semantic conventions:

- `gen_ai.provider.name` identifies the LLM provider (replaces deprecated `gen_ai.system`).
- Metrics:
  - `gen_ai.client.operation.duration` (histogram, unit `s`)
  - `gen_ai.client.token.usage` (histogram, unit `{token}`)
- After Prometheus sanitization the metric names become:
  - `gen_ai_client_operation_duration_seconds_*`
  - `gen_ai_client_token_usage_*`
- Labels after sanitization:
  - `gen_ai_provider_name`
  - `gen_ai_request_model`
  - `gen_ai_token_type`

## Architecture

```
Agent App  ──OTLP──▶  OTel Collector  ──OTLP──▶  GreptimeDB  ◀── Grafana
 (localhost:4318)      (buffering, batching)      (storage)      (dashboard)
```

The Agent app emits OTLP telemetry (traces + logs) which is received by the
OTel Collector. The Collector batches, retries, and forwards the data to
GreptimeDB's OTLP HTTP endpoint. Grafana queries GreptimeDB for visualization.

This follows the [GreptimeDB recommended pattern](https://docs.greptime.cn/user-guide/ingest-data/for-observability/otel-collector):
using an OTel Collector as the ingestion gateway provides buffering,
backpressure handling, and decouples the app from the storage backend.

## Quick Start

```bash
# Start OTel Collector + GreptimeDB + Grafana
docker compose up -d

# (Optional) Start the load generator and create Flow aggregations
docker compose --profile load up -d
```

## Endpoints

| Service              | URL                                   |
|----------------------|---------------------------------------|
| Grafana              | http://localhost:3000 (admin / admin) |
| OTel Collector HTTP  | http://localhost:4318                 |
| OTel Collector gRPC  | localhost:4317                        |
| GreptimeDB HTTP API  | http://localhost:4000                 |
| GreptimeDB gRPC      | localhost:4001                        |
| GreptimeDB MySQL     | mysql -h 127.0.0.1 -P 4002            |

## Dashboard

The `Agent Observability (GreptimeDB)` dashboard (uid `agent-observability-greptime`)
combines:

- **SQL** — traces, logs (`genai_conversations`), and Flow aggregation tables via the MySQL datasource.
- **PromQL** — OTel histogram metrics via the Prometheus-compatible datasource.
- **Trace waterfall** — via the GreptimeDB Grafana plugin datasource.

## Flow Aggregations

`flows.sql` creates continuous materialized views:

- `genai_token_usage_1m` — token counts per model per minute
- `genai_latency_1m` — latency distribution per model per minute
- `genai_status_1m` — request counts by model and status per minute

Run them automatically with the `load` profile, or execute `init-flow.sh` manually
once GreptimeDB is healthy.

## Model Pricing

`pricing.sql` seeds the `model_pricing` table used by the cost panels.
It is loaded automatically by the `init-pricing` container when GreptimeDB
becomes healthy, or you can run `init-pricing.sh` manually.

Update the prices in `pricing.sql` when providers change their rate cards.

## Trace / Log Filter

To find GenAI spans in SQL:

```sql
SELECT * FROM opentelemetry_traces
WHERE span_attributes.gen_ai.provider.name IS NOT NULL;
```

Conversation logs are stored in `genai_conversations`. Expected body formats:

- user/tool: `{"content":"..."}`
- assistant: `{"index":0,"message":{"role":"assistant","content":"..."}}`

## Cleanup

```bash
docker compose --profile load down -v
docker compose down -v
```
