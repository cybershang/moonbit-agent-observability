///|
async fn main {
  // Step 2: Direct POST to StepFun API with a simple message
  let api_key = "YOUR_API_KEY"
  let body : Map[String, Json] = {}
  body["model"] = "step-3.7-flash".to_json()
  body["messages"] = [
    { "role": "user", "content": "你好" },
  ].to_json()
  body["max_tokens"] = (256).to_json()
  let headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + api_key,
  }
  let (response, resp_body) = @http.post(
    "https://api.stepfun.com/v1/chat/completions",
    Json::object(body),
    headers~,
  )
  @debug.debug(response.code)
  let data = resp_body.json()
  @debug.debug(data)
}
