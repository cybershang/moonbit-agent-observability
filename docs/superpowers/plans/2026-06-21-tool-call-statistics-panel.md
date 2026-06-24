# Tool Call Statistics Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit a tool-registration log at agent startup and add a Grafana table panel that shows every registered tool, its call count, and average execution duration.

**Architecture:** Startup logs write one record per registered tool to `opentelemetry_logs`; the dashboard derives the full tool list from those logs and `LEFT JOIN`s `opentelemetry_traces` for execution statistics.

**Tech Stack:** MoonBit native, GreptimeDB, Grafana, OpenTelemetry logs/traces.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `agent-observability/cmd/main/moon.pkg` | Import the OpenTelemetry `common` package so `main.mbt` can construct log attributes. |
| `agent-observability/cmd/main/main.mbt` | Loop over `@agent.tools` after `Agent::new` and emit a `Tool registered` log per tool. |
| `agent-observability/deploy/greptime/grafana/dashboards/genai.json` | Add the `Tool Call Statistics` table panel under the **Registered Tools** stat and move the two existing timeseries panels down to avoid overlap. |

---

## Task 1: Import OpenTelemetry common types in the main package

**Files:**
- Modify: `agent-observability/cmd/main/moon.pkg`

- [ ] **Step 1: Add the `@common` import**

```moonbit
import {
  "cybershang/agent-observability" @agent,
  "cybershang/agent-telemetry" @telemetry,
  "moonbit-community/opentelemetry/interface/common" @common,
  "moonbitlang/async",
  "moonbitlang/async/stdio",
  "moonbitlang/core/argparse",
}

options(
  "is-main": true,
)
```

- [ ] **Step 2: Verify the package imports cleanly**

Run:
```bash
cd agent-observability && moon check cmd/main
```

Expected: no import errors.

---

## Task 2: Emit tool-registration logs at startup

**Files:**
- Modify: `agent-observability/cmd/main/main.mbt`

- [ ] **Step 1: Add the registration log loop after `Agent::new`**

Locate this block in `main.mbt`:

```moonbit
  let agent = @agent.Agent::new(
    client,
    tools=@agent.tools,
    max_tool_turns=settings.max_tool_turns,
  )
```

Insert immediately after it:

```moonbit
  // Emit a registration log for every known tool. The dashboard uses these
  // logs to build the complete tool list (including zero-call tools).
  for tool in @agent.tools {
    @telemetry.log_info(
      "cybershang/agent-observability/tools",
      "Tool registered",
      attributes=[
        @common.KeyValue::new("gen_ai.tool.name", String(tool.name)),
      ],
    )
  }
```

- [ ] **Step 2: Build the main target**

Run:
```bash
cd agent-observability && moon build --target native cmd/main
```

Expected: build succeeds.

---

## Task 3: Test the SQL query before changing the dashboard

**Files:**
- None (manual verification)

- [ ] **Step 1: Run the agent once to generate startup logs**

With GreptimeDB running (`docker compose up -d` in `deploy/greptime` if needed), run:

```bash
cd agent-observability && moon run --target native cmd/main -- --ask "What is the weather in Beijing?"
```

Expected: agent completes and exits; telemetry is flushed by the existing `force_flush()`/`shutdown()` calls.

- [ ] **Step 2: Query for the startup logs**

```bash
curl -s -X POST "http://localhost:4000/v1/sql?db=public" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "sql=SELECT body, json_get_string(log_attributes, '$."gen_ai.tool.name"') AS tool FROM opentelemetry_logs WHERE body = 'Tool registered'"
```

Expected: three rows with tools `get_weather`, `lookup_city`, `execute_command`.

- [ ] **Step 3: Run the full panel query and confirm zero-call tools appear**

```bash
curl -s -X POST "http://localhost:4000/v1/sql?db=public" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "sql=WITH registered_tools AS (SELECT DISTINCT json_get_string(log_attributes, '$."gen_ai.tool.name"') AS tool FROM opentelemetry_logs WHERE body = 'Tool registered' AND scope_name = 'cybershang/agent-observability/tools') SELECT r.tool AS Tool, COUNT(t.span_id) AS Calls, ROUND(AVG(t.duration_nano) / 1000000.0, 2) AS \`Avg Duration (ms)\` FROM registered_tools r LEFT JOIN opentelemetry_traces t ON t.span_name = 'gen_ai.tool.execution' AND t.\`span_attributes.gen_ai.tool.name\` = r.tool AND timestamp >= NOW() - INTERVAL '1 hour' GROUP BY r.tool ORDER BY Calls DESC"
```

Expected: all three tools listed; `Calls` reflects executions in the last hour, with zero for any tool not called.

---

## Task 4: Add the Grafana table panel

**Files:**
- Modify: `agent-observability/deploy/greptime/grafana/dashboards/genai.json`

- [ ] **Step 1: Insert the new panel after the "Registered Tools" stat panel**

Locate the closing `}` of the **Registered Tools** panel (currently at `y = 103`). Insert the following panel object right after it:

```json
    {
      "type": "table",
      "title": "Tool Call Statistics",
      "gridPos": {
        "h": 8,
        "w": 6,
        "x": 0,
        "y": 107
      },
      "datasource": {
        "type": "mysql",
        "uid": "${DS_GREPTIMEDB}"
      },
      "targets": [
        {
          "editorMode": "code",
          "rawSql": "WITH registered_tools AS (SELECT DISTINCT json_get_string(log_attributes, '$."gen_ai.tool.name"') AS tool FROM opentelemetry_logs WHERE body = 'Tool registered' AND scope_name = 'cybershang/agent-observability/tools') SELECT r.tool AS Tool, COUNT(t.span_id) AS Calls, ROUND(AVG(t.duration_nano) / 1000000.0, 2) AS `Avg Duration (ms)` FROM registered_tools r LEFT JOIN opentelemetry_traces t ON t.span_name = 'gen_ai.tool.execution' AND t.`span_attributes.gen_ai.tool.name` = r.tool AND $__timeFilter(t.timestamp) GROUP BY r.tool ORDER BY Calls DESC",
          "format": "table",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "custom": {
            "align": "auto",
            "displayMode": "auto"
          }
        },
        "overrides": []
      },
      "options": {
        "showHeader": true
      }
    },
```

- [ ] **Step 2: Move the two timeseries panels down to make room**

Find **Prompt & Response Length Trend** (`"type": "timeseries"`) and change:

```json
        "y": 107
```

to:

```json
        "y": 115
```

Find **Tool Result Length Trend** (`"type": "timeseries"`) and make the same change (`107` → `115`).

- [ ] **Step 3: Validate the dashboard JSON**

Run:
```bash
python3 -m json.tool agent-observability/deploy/greptime/grafana/dashboards/genai.json > /dev/null
```

Expected: no output (valid JSON) and exit code 0.

---

## Task 5: Verify the dashboard

**Files:**
- None (manual verification)

- [ ] **Step 1: Reload or import the dashboard in Grafana**

The dashboard is provisioned from `deploy/greptime/grafana/dashboards/genai.json`; restart the Grafana container or re-import the dashboard so the new panel loads.

- [ ] **Step 2: Confirm panel contents**

Open the **Application Attributes** row and check the **Tool Call Statistics** table:

- All three tools appear (`get_weather`, `lookup_city`, `execute_command`).
- `Calls` matches the number of `gen_ai.tool.execution` spans in the selected time range.
- `Avg Duration (ms)` is computed from `duration_nano`.

- [ ] **Step 3: Check zero-call behavior**

Select a time range before any tool execution but after the startup logs were emitted. Confirm every registered tool still appears with `Calls = 0`.

---

## Task 6: Run the test suite

**Files:**
- None (existing tests)

- [ ] **Step 1: Run MoonBit tests**

```bash
cd agent-observability && moon test
```

Expected: all tests pass (current baseline is 78/78).

---

## Spec Coverage Check

| Spec Requirement | Task |
|------------------|------|
| Startup log per registered tool | Task 2 |
| Log scope, body, and attribute values | Task 2 |
| Grafana table panel under **Registered Tools** | Task 4 |
| Table columns: Tool, Calls, Avg Duration (ms) | Task 4 |
| Zero-call tools still shown | Task 3 / Task 5 |
| Existing timeseries moved down to avoid overlap | Task 4 |
| Verify with queries and tests | Task 3 / Task 5 / Task 6 |

## Placeholder Scan

- No `TBD`, `TODO`, or "implement later" entries.
- All code snippets are concrete and use the actual tool names (`get_weather`, `lookup_city`, `execute_command`).
- All file paths are exact.
- All commands include expected outputs.

## Type Consistency Check

- `@telemetry.log_info` signature accepts `Array[@common.KeyValue]`; the added `@common` import matches the attribute constructor used.
- `tool.name` is a `String` field on the `Tool` struct exported by `@agent`.
- Dashboard query columns match the aliases used in the panel.
