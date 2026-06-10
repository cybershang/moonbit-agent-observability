// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| Read a `.env` file and look up a key.
pub async fn read_dotenv(key : String) -> String? {
  let content = try {
    (@fs.read_file(".env").text() : String)
  } catch {
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
