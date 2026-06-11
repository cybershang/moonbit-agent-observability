// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
/// Application settings loaded from environment variables or `.env` file.
pub struct Settings {
  // LLM provider
  provider_name : String
  base_url : String
  model : String
  api_key : String
  max_tokens : Int
  // Agent behavior
  max_tool_turns : Int
  // Observability
  otel_stdout : Bool
  capture_content : Bool
}

///|
/// Load settings from environment variables or `.env` file.
pub async fn Settings::from_env() -> Settings {
  let api_key = env("LLM_API_KEY")
  let provider_name = env("LLM_PROVIDER", default="stepfun")
  let base_url = env("LLM_BASE_URL", default="https://api.stepfun.com/v1")
  let model = env("LLM_MODEL", default="step-3.7-flash")
  let max_tokens = parse_int(env("LLM_MAX_TOKENS", default="1024"), 1024)
  let max_tool_turns = parse_int(env("AGENT_MAX_TOOL_TURNS", default="10"), 10)
  let otel_stdout = env("OTEL_STDOUT").to_lower() == "true"
  let capture_content = env("CAPTURE_CONTENT").to_lower() == "true"
  {
    provider_name,
    base_url,
    model,
    api_key,
    max_tokens,
    max_tool_turns,
    otel_stdout,
    capture_content,
  }
}

///|
/// Read a `.env` file and look up a key.
pub async fn read_dotenv(key : String) -> String? {
  let content = (@fs.read_file(".env").text() : String) catch {
    _ => return None
  }
  for line in content.split("\n") {
    let trimmed = line.trim(char_set="\r ")
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    match trimmed.split_once("=") {
      Some((k, v)) => if k == key { return Some(v.to_owned()) }
      None => continue
    }
  }
  None
}

///|
/// Read a configuration value from the process environment or `.env` file.
///
/// Resolution order: process environment > `.env` file > default.
pub async fn env(key : String, default? : String = "") -> String {
  match @env.get_env_var(key) {
    Some(value) => value
    None => read_dotenv(key).unwrap_or(default)
  }
}

///|
/// Parse an integer from a string, returning the default on failure.
pub fn parse_int(s : String, default : Int) -> Int {
  match s.trim() {
    "" => default
    text => @string.parse_int(text) catch { _ => default }
  }
}
