///|
async fn main {
  let (response, body) = @http.get("https://jsonplaceholder.typicode.com/todos/1")
  @debug.debug(response.code)
  let data = body.json()
  let number_opt = if data is { "id": Number(id, ..), .. } {
    Some(id)
  } else {
    None
  }
  @debug.debug(number_opt)
}
