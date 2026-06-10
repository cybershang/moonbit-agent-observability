///|
async fn main {
  // Step 3: Two-round conversation with StepFun API
  let api_key = "YOUR_API_KEY"
  let messages : Array[Map[String, Json]] = []

  // Round 1: user asks about Beijing weather
  messages.push({ "role": "user", "content": "北京今天天气怎么样？" })
  let body1 = build_body(messages, api_key)
  let (response1, resp_body1) = @http.post(
    "https://api.stepfun.com/v1/chat/completions",
    body1,
    headers={
      "Content-Type": "application/json",
      "Authorization": "Bearer " + api_key,
    },
  )
  @debug.debug(response1.code)
  let data1 = resp_body1.json()
  @debug.debug(data1)

  // Extract assistant reply and append to history
  let reply1 = extract_content(data1)
  messages.push({ "role": "assistant", "content": reply1 })

  // Round 2: user follows up
  messages.push({ "role": "user", "content": "那上海呢？" })
  let body2 = build_body(messages, api_key)
  let (response2, resp_body2) = @http.post(
    "https://api.stepfun.com/v1/chat/completions",
    body2,
    headers={
      "Content-Type": "application/json",
      "Authorization": "Bearer " + api_key,
    },
  )
  @debug.debug(response2.code)
  let data2 = resp_body2.json()
  @debug.debug(data2)
}

///| Build request JSON from message history.
fn build_body(messages : Array[Map[String, Json]], _api_key : String) -> Json {
  let body : Map[String, Json] = {}
  body["model"] = "step-3.7-flash".to_json()
  body["messages"] = messages.to_json()
  body["max_tokens"] = (256).to_json()
  Json::object(body)
}

///| Extract the assistant content string from the response JSON.
fn extract_content(data : Json) -> String {
  guard data is {
    "choices": Array([
      { "message": { "content": String(content), .. }, .. },
      ..
    ]),
    ..
  } else {
    return ""
  }
  content
}
