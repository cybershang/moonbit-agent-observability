///|
async fn main {
  // Step 5: Use structured Message and LLMResponse types
  let api_key = "YOUR_API_KEY"
  let messages : Array[@agent.Message] = []

  // Round 1
  messages.push(@agent.Message::new(content=Some("北京今天天气怎么样？")))
  let response1 = @agent.llm_request(messages, api_key)
  @debug.debug(response1)
  match response1.content {
    Some(content) => messages.push(@agent.Message::new(role="assistant", content=Some(content)))
    None => ()
  }

  // Round 2
  messages.push(@agent.Message::new(content=Some("那上海呢？")))
  let response2 = @agent.llm_request(messages, api_key)
  @debug.debug(response2)
  match response2.content {
    Some(content) => @stdio.stdout.write(content)
    None => ()
  }
}
