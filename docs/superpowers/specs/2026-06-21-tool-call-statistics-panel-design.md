# Design: Tool Call Statistics Panel

**Date:** 2026-06-21  
**Project:** agent-observability (MoonBit native agent with GreptimeDB/Grafana observability)  
**Status:** Approved by user

## Goal

Add a Grafana table panel that lists every tool registered by the agent, along with:
1. how many times each tool was called in the selected time range, and
2. the average execution duration in milliseconds.

The panel should also populate the currently sparse `opentelemetry_logs` table by emitting a registration log at agent startup.

## Background

- Tool execution is already traced as `gen_ai.tool.execution` spans in `opentelemetry_traces`.
- Trace attributes are flattened by the `greptime_trace_v1` pipeline, so the tool name is available as `` `span_attributes.gen_ai.tool.name` ``.
- `opentelemetry_logs` exists but receives very few records today.
- The existing dashboard already has an **Application Attributes** row with a **Registered Tools** stat panel.

## Design

### 1. Startup tool-registration logs

When the agent finishes telemetry initialization and creates the `Agent`, it iterates over `@agent.tools` and emits one INFO log per tool:

- `scope_name`: `cybershang/agent-observability/tools`
- `body`: `Tool registered`
- `log_attributes`: `{"gen_ai.tool.name": "<tool-name>"}`

Implementation location: `agent-observability/cmd/main/main.mbt`, right after `Agent::new(...)`.

These logs land in the default `opentelemetry_logs` table. Because GreptimeDB stores `log_attributes` as JSON, the dashboard query uses `json_get_string(log_attributes, '$."gen_ai.tool.name"')` to extract the tool name.

### 2. Dashboard panel: "Tool Call Statistics"

A new `table` panel is added under the **Application Attributes** row, directly below the existing **Registered Tools** stat panel.

#### Layout

- **Row:** `Application Attributes` (existing, starts at `y = 102`)
- **Registered Tools** stat: `x = 0, y = 103, w = 6, h = 4` (existing)
- **Tool Call Statistics** table: `x = 0, y = 107, w = 6, h = 8` (new)
- **Prompt & Response Length Trend** timeseries: moved from `y = 107` to `y = 115`
- **Tool Result Length Trend** timeseries: moved from `y = 107` to `y = 115` (kept side-by-side with the above)

#### Query

```sql
WITH registered_tools AS (
  SELECT DISTINCT
    json_get_string(log_attributes, '$."gen_ai.tool.name"') AS tool
  FROM opentelemetry_logs
  WHERE body = 'Tool registered'
    AND scope_name = 'cybershang/agent-observability/tools'
)
SELECT
  r.tool AS "Tool",
  COUNT(t.span_id) AS "Calls",
  ROUND(AVG(t.duration_nano) / 1000000.0, 2) AS "Avg Duration (ms)"
FROM registered_tools r
LEFT JOIN opentelemetry_traces t
  ON t.span_name = 'gen_ai.tool.execution'
  AND t.`span_attributes.gen_ai.tool.name` = r.tool
  AND $__timeFilter(t.timestamp)
GROUP BY r.tool
ORDER BY "Calls" DESC
```

Notes:
- The `registered_tools` CTE intentionally does **not** use `$__timeFilter(timestamp)`. Startup logs may fall outside the dashboard time range, and we still want zero-call tools to appear.
- Tool execution spans are filtered by `$__timeFilter(timestamp)` so call counts and durations reflect the selected window.
- `duration_nano` is converted to milliseconds.

#### Columns

| Column | Unit / type |
|--------|--------------|
| Tool   | string |
| Calls  | short integer |
| Avg Duration (ms) | milliseconds (`ms`) |

### 3. Code changes

1. `agent-observability/cmd/main/main.mbt`
   - After creating the `Agent`, loop over `tools` and call `@telemetry.log_info(...)` for each.
2. `agent-observability/deploy/greptime/grafana/dashboards/genai.json`
   - Add the new `table` panel.
   - Adjust the `gridPos.y` of **Prompt & Response Length Trend** from `107` to `115`.

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| `json_get_string` is GreptimeDB-specific and may not work in other backends | This dashboard already targets GreptimeDB exclusively. |
| Startup logs from removed tools linger and appear in the table | Acceptable for now; if tool set changes frequently, a retention policy or a dedicated `tool_registry` table can be introduced later. |
| Non-interactive (`--ask`) mode exits before logs flush | `force_flush()` is already called after the turn and `shutdown()` runs before exit. |

## Verification

1. Build and run the agent with `--ask` or REPL.
2. Query GreptimeDB and confirm `opentelemetry_logs` contains rows with `body = 'Tool registered'` and `log_attributes["gen_ai.tool.name"]` set.
3. Open Grafana, select a time range that includes some tool executions, and confirm the table shows all registered tools with correct call counts and average durations.
4. Select a time range with no executions and confirm all tools still appear with `Calls = 0`.
5. Run `moon test` to ensure existing tests still pass.

## Future extensions

- Add a `tool_registry` SQL table if the number of tools grows or if dynamic registration is needed.
- Add an error-count column by joining on `span_status = 'STATUS_CODE_ERROR'`.
