// gleam
import gleam/list
import gleam/uri

// gleeunit
import gleeunit/should

// sqlight
import sqlight

// me
import database/sql.{
  exec_migrations, read_migrations, to_connection, with_connection,
}

pub fn read_migrations_ok_test() {
  let migrations =
    read_migrations(in: "./test/database/testdata/good")
    |> should.be_ok

  // length
  migrations
  |> list.length
  |> should.equal(3)
}

pub fn read_migrations_error_test() {
  read_migrations(in: "./never")
  |> should.be_error
}

pub fn exec_migration_error_test() {
  // url params
  use conn <- with_connection(":memory:")
  conn
  |> exec_migrations("./test/database/testdata/bad", on: _)
  |> should.be_error
}

pub fn exec_migration_ok_test() {
  use conn <- with_connection(":memory:")
  conn
  |> exec_migrations("./test/database/testdata/good", on: _)
  |> should.be_ok
}
