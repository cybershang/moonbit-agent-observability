///|
async fn main {
  // Step 4: Use the abstracted llm_request helper
  let api_key = "YOUR_API_KEY"
  let messages : Array[Map[String, Json]] = []

  // Round 1
  messages.push({ "role": "user", "content": "北京今天天气怎么样？" })
  let data1 = @agent.llm_request(messages, api_key)
  @debug.debug(data1)
  let reply1 = @agent.extract_content(data1)
  messages.push({ "role": "assistant", "content": reply1 })

  // Round 2
  messages.push({ "role": "user", "content": "那上海呢？" })
  let data2 = @agent.llm_request(messages, api_key)
  @debug.debug(data2)
  let reply2 = @agent.extract_content(data2)
  @stdio.stdout.write(reply2)
}
