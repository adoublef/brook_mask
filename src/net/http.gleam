import gleam/string_builder
import wisp

pub fn handle(_: wisp.Request) -> wisp.Response {
  let body = string_builder.from_string("<h1>Hello, World</h1>")
  wisp.html_response(body, 200)
}
