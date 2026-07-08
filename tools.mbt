// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| Tool registry

///|
/// A tool handler takes a JSON arguments string and returns a result string.
pub type ToolHandler = async (String) -> String

///|
/// A tool definition bundled with its runtime handler.
pub struct RegisteredTool {
  tool : Tool
  handler : ToolHandler
}

///|
/// Single source of truth for all available tools.
let registered_tools : Array[RegisteredTool] = [
  {
    tool: Tool::new(
      name="get_weather",
      description="Get the current weather for a location. You must first use lookup_city to obtain a location_id, then pass it here.",
      parameters={
        "type": "object",
        "properties": {
          "location_id": {
            "type": "string",
            "description": "QWeather Location ID, e.g. 101010100 for Beijing",
          },
          "city": {
            "type": "string",
            "description": "Optional city name for display purposes",
          },
        },
        "required": ["location_id"],
      },
    ),
    handler: get_weather,
  },
  {
    tool: Tool::new(
      name="execute_command",
      description="Execute a command in the system shell and return stdout. Only safe read-only commands (e.g. ls, cat, echo, pwd) are allowed; commands that modify the system (e.g. rm, mv, cp, write) are forbidden.",
      parameters={
        "type": "object",
        "properties": {
          "command": {
            "type": "string",
            "description": "The shell command to execute (e.g. ls -la)",
          },
        },
        "required": ["command"],
      },
    ),
    handler: execute_command_tool,
  },
  {
    tool: Tool::new(
      name="lookup_city",
      description="Look up a city or location in QWeather GeoAPI and return candidate location IDs. Use this before get_weather.",
      parameters={
        "type": "object",
        "properties": {
          "query": {
            "type": "string",
            "description": "City name, district, or location keyword to search",
          },
          "adm": {
            "type": "string",
            "description": "Optional superior administrative division to disambiguate, e.g. 'beijing' or '内蒙古'",
          },
        },
        "required": ["query"],
      },
    ),
    handler: lookup_city,
  },
]

///|
/// Tool definitions exposed to the LLM.
pub let tools : Array[Tool] = registered_tools.map(fn(r) { r.tool })

///|
/// Registry mapping tool names to their handlers.
let tool_registry : Map[String, ToolHandler] = Map::from_array(
  registered_tools.map(fn(r) { (r.tool.name, r.handler) }),
)

///|
/// Execute a tool by name with JSON arguments.
pub async fn execute_tool(
  name : String,
  arguments : String,
  parent_context? : @context.Context = @context.Context::empty(),
) -> String {
  let tracer = @telemetry.tracer("cybershang/agent-o11y-demo/tools")
  let meter = @telemetry.meter("cybershang/agent-o11y-demo/tools")
  let span = @telemetry.start_tool_span(
    tracer,
    name,
    arguments,
    parent_context~,
  )

  let result = match tool_registry.get(name) {
    Some(handler) => handler(arguments)
    None => "{\"error\": \"Unknown tool: " + name + "\"}"
  }
  @telemetry.set_int(span, "app.tool.result.length", result.length().to_int64())

  let success = !result.contains("\"error\"")
  @telemetry.record_tool_call(meter, name, success~)
  if !success {
    @telemetry.log_error(
      "cybershang/agent-o11y-demo/tools",
      "Tool \{name} returned error: " + result,
      trace_context=Some(span.span_context()),
    )
  }

  @telemetry.set_tool_result(span, result)
  @telemetry.end_span(span)

  result
}

///|
/// Read the QWeather API host from env and ensure it has a protocol prefix.
async fn qweather_host() -> String {
  let host = env("QWEATHER_API_HOST", default="https://devapi.qweather.com")
  let host = host.trim(char_set="/").to_owned()
  if host.has_prefix("http://") || host.has_prefix("https://") {
    host
  } else {
    "https://" + host
  }
}

///|
/// Return true when a QWeather credential (JWT token or legacy API key) is configured.
async fn qweather_configured() -> Bool {
  let token = env("QWEATHER_TOKEN")
  let key = env("QWEATHER_API_KEY")
  !token.is_empty() || !key.is_empty()
}

///|
/// Perform an authorized GET against the QWeather API and return the parsed JSON.
/// Supports both Platform JWT (Authorization: Bearer) and legacy Web API key (?key=).
async fn qweather_get(path : String) -> (@http.Response, Json) {
  let host = qweather_host()
  let token = env("QWEATHER_TOKEN")
  let api_key = env("QWEATHER_API_KEY")
  let mut full_path = path
  let headers : Map[String, String] = {}
  if !token.is_empty() {
    headers["Authorization"] = "Bearer " + token
  } else if !api_key.is_empty() {
    full_path = full_path + "&key=" + url_encode(api_key)
  } else {
    return (
      { code: 401, reason: "Unauthorized", headers: {}, cookies: [] },
      Json::object({
        "error": "QWEATHER_TOKEN or QWEATHER_API_KEY not configured".to_json(),
      }),
    )
  }
  let (response, body) = @http.get(host + full_path, headers~)
  (response, body.json())
}

///|
/// Look up a city or location in QWeather GeoAPI and return candidate locations.
async fn lookup_city(args_json : String) -> String {
  let args = @json.parse(args_json) catch {
    _ => return "{\"error\": \"Invalid JSON arguments\"}"
  }
  let query = if args is { "query": String(q), .. } {
    q
  } else {
    return "{\"error\": \"Missing 'query' field\"}"
  }
  let adm = if args is { "adm": String(a), .. } { a } else { "" }
  if !qweather_configured() {
    return "{\"error\": \"QWEATHER_TOKEN (or QWEATHER_API_KEY) not configured\"}"
  }
  let mut path = "\{geo_path()}?location=\{url_encode(query)}"
  if !adm.is_empty() {
    path = path + "&adm=" + url_encode(adm)
  }
  path = path + "&number=10"
  let (resp, data) = qweather_get(path)
  if resp.code != 200 {
    return "{\"error\": \"QWeather GeoAPI request failed: HTTP \{resp.code}\"}"
  }
  guard data is { "code": String("200"), "location": Array(locations), .. } else {
    return "{\"error\": \"QWeather GeoAPI returned unexpected format\"}"
  }
  if locations.is_empty() {
    return "{\"error\": \"No locations found for: \{escape_json(query)}\"}"
  }
  let candidates = locations.map(fn(loc) {
    let name = if loc is { "name": String(n), .. } { n } else { "" }
    let id = if loc is { "id": String(i), .. } { i } else { "" }
    let adm1 = if loc is { "adm1": String(a), .. } { a } else { "" }
    let adm2 = if loc is { "adm2": String(a), .. } { a } else { "" }
    let country = if loc is { "country": String(c), .. } { c } else { "" }
    "{\"name\":\"" +
    escape_json(name) +
    "\",\"id\":\"" +
    escape_json(id) +
    "\",\"adm1\":\"" +
    escape_json(adm1) +
    "\",\"adm2\":\"" +
    escape_json(adm2) +
    "\",\"country\":\"" +
    escape_json(country) +
    "\"}"
  })
  "[\{candidates.join(",")}]"
}

///|
/// Return the GeoAPI path prefix.
fn geo_path() -> String {
  "/geo/v2/city/lookup"
}

///|
/// Query QWeather for the current weather of a location.
async fn get_weather(args_json : String) -> String {
  let args = @json.parse(args_json) catch {
    _ => return "{\"error\": \"Invalid JSON arguments\"}"
  }
  let location_id = if args is { "location_id": String(id), .. } {
    id
  } else {
    return "{\"error\": \"Missing 'location_id' field. Use lookup_city first.\"}"
  }
  let city = if args is { "city": String(c), .. } { c } else { "" }

  if !qweather_configured() {
    return "{\"error\": \"QWEATHER_TOKEN (or QWEATHER_API_KEY) not configured\"}"
  }

  let path = "/v7/weather/now?location=" + url_encode(location_id)
  let (resp, data) = qweather_get(path)
  if resp.code != 200 {
    return "{\"error\": \"QWeather weather API failed: HTTP \{resp.code}\"}"
  }
  guard data is { "code": String("200"), "now": now_obj, .. } else {
    return "{\"error\": \"QWeather weather API returned unexpected format\"}"
  }
  guard now_obj is { "temp": String(temp), "text": String(text), .. } else {
    return "{\"error\": \"QWeather weather data missing temp/text\"}"
  }
  let wind_dir = if now_obj is { "windDir": String(wd), .. } { wd } else { "" }
  let humidity = if now_obj is { "humidity": String(h), .. } { h } else { "" }

  "{\"location_id\":\"" +
  escape_json(location_id) +
  "\",\"city\":\"" +
  escape_json(city) +
  "\",\"temperature\":\"" +
  escape_json(temp) +
  "\",\"condition\":\"" +
  escape_json(text) +
  "\",\"wind\":\"" +
  escape_json(wind_dir) +
  "\",\"humidity\":\"" +
  escape_json(humidity) +
  "\"}"
}

///|
/// Percent-encode a string for use in a URL query parameter.
fn url_encode(s : String) -> String {
  let bytes = @utf8.encode(s)
  let sb = StringBuilder::new()
  let hex = "0123456789ABCDEF"
  for i in 0..<bytes.length() {
    let b = bytes[i].to_int()
    if (b >= 'A'.to_int() && b <= 'Z'.to_int()) ||
      (b >= 'a'.to_int() && b <= 'z'.to_int()) ||
      (b >= '0'.to_int() && b <= '9'.to_int()) ||
      b == '-'.to_int() ||
      b == '_'.to_int() ||
      b == '.'.to_int() ||
      b == '~'.to_int() {
      sb.write_char(Int::unsafe_to_char(b))
    } else {
      sb.write_char('%')
      sb.write_char(Int::unsafe_to_char(hex[b >> 4].to_int()))
      sb.write_char(Int::unsafe_to_char(hex[b & 0xF].to_int()))
    }
  }
  sb.to_string()
}

///|
/// Execute a shell command and return stdout as string.
async fn execute_command_tool(args_json : String) -> String {
  let args = @json.parse(args_json) catch {
    _ => return "{\"error\": \"Invalid JSON arguments\"}"
  }
  let command = if args is { "command": String(cmd), .. } {
    cmd
  } else {
    return "{\"error\": \"Missing 'command' field\"}"
  }
  // Security: reject dangerous commands
  let forbidden = [
    "rm", "mv", "cp", "dd", "mkfs", "fdisk", "format", "del", "rd", "rmdir",
  ]
  let cmd_lower = command.trim().to_lower()
  for bad in forbidden {
    if cmd_lower.has_prefix(bad + " ") || cmd_lower == bad {
      return "{\"error\": \"Forbidden command: " + bad + "\"}"
    }
  }
  // Run command and collect output. Use lossy UTF-8 decoding so commands that
  // emit binary data (e.g. `cat` on a non-text file) do not crash the agent.
  let (code, stdout, _stderr) = @process.collect_output("sh", ["-c", command])
  let output = @utf8.decode_lossy(stdout.binary())
  "{\"exit_code\": " +
  code.to_string() +
  ", \"output\": \"" +
  escape_json(output) +
  "\"}"
}

///|
/// Escape special characters in a JSON string value.
fn escape_json(s : String) -> String {
  let sb = StringBuilder::new()
  for ch in s {
    match ch {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}
