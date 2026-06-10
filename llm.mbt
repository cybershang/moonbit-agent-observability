///| Send a single request to the LLM with a message history.
pub async fn llm_request(
  messages : Array[Map[String, Json]],
  api_key : String,
  model_name~ : String = "step-3.7-flash",
  max_tokens~ : Int = 1024,
) -> Json {
  let body : Map[String, Json] = {}
  body["model"] = model_name.to_json()
  body["messages"] = messages.to_json()
  body["max_tokens"] = max_tokens.to_json()
  let (response, resp_body) = @http.post(
    "https://api.stepfun.com/v1/chat/completions",
    Json::object(body),
    headers={
      "Content-Type": "application/json",
      "Authorization": "Bearer " + api_key,
    },
  )
  guard response.code == 200 else {
    abort("LLM request failed with status: \{response.code}")
  }
  resp_body.json()
}

///| Extract the assistant content string from the response JSON.
pub fn extract_content(data : Json) -> String {
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
