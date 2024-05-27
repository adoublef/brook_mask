// gleam
import gleam/dynamic
import gleam/result
import gleam/string_builder

// wisp
import wisp

// database
import database/sql

pub type Context {
  Context(db: sql.Connection)
}

pub fn handle_request(_req: wisp.Request, ctx: Context) -> wisp.Response {
  let Context(db) = ctx

  let assert [html] =
    sql.query(
      "select '<h1>Hello, World</h1>'",
      on: db,
      with: [],
      expecting: dynamic.element(0, dynamic.string),
    )
    |> result.unwrap(["<div>Error</div>"])

  let body = string_builder.from_string(html)
  wisp.html_response(body, 200)
}
