// gleam
import gleam/io

// gleeunit
import gleeunit/should

// sqlight
import sqlight

// me
import database/sql

pub fn read_migrations_test() {
  sql.read_migrations(from: "./test/database/testdata")
  |> should.be_ok
}

pub fn read_migrations_fail_test() {
  sql.read_migrations(from: "./not_exist")
  |> should.be_error
}

pub fn with_transaction_test() {
  // use can lead to a panic?
  use conn <- sqlight.with_connection(":memory:")
  let assert Ok(_) = sqlight.exec("BEGIN TRANSACTION;", on: conn)
  let migration =
    "
    create table test (v text) strict;
    "
  // ddo somthing
  case sqlight.exec(migration, on: conn) {
    Ok(_) -> {
      io.debug("commit")
      sqlight.exec("COMMIT", on: conn)
    }
    Error(_) -> {
      io.debug("rollback")
      sqlight.exec("ROLLBACK", on: conn)
    }
  }
}

pub fn exec_migration_error_test() {
  // url params
  use conn <- sqlight.with_connection(":memory:")
  sql.exec_migration("./test/database/testdata/bad", on: conn)
  |> should.be_error
}

pub fn exec_migration_ok_test() {
  // url params
  use conn <- sqlight.with_connection(":memory:")
  sql.exec_migration("./test/database/testdata/good", on: conn)
  |> should.be_ok
}
