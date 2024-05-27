// gleam
import gleam/dynamic
import gleam/io
import gleam/list
import gleam/result
import gleam/string

// simplifile
import simplifile

//sqlight
import sqlight

/// Error
pub type Error {
  /// FileError is returned when there is a fault File System error
  FileError(simplifile.FileError)
  /// Sqlight is returned where an error with a SQL operation occurs
  SQLiteError(sqlight.Error)
  /// NoRows
  NoRows
}

/// read_migrations reads migration files from a directory.
pub fn read_migrations(from filepath: String) -> Result(List(String), Error) {
  // possible to cast error
  use entries <- result.try(
    simplifile.get_files(in: filepath)
    |> result.map_error(FileError),
  )
  entries
  |> list.sort(string.compare)
  |> list.try_map(simplifile.read)
  |> result.map_error(FileError)
}

/// exec_migration executes migrations on a sqlite table
pub fn exec_migration(
  from filepath: String,
  on conn: sqlight.Connection,
) -> Result(Nil, Error) {
  let assert Ok(migrations) = read_migrations(from: filepath)
  use <- with_transaction(conn)
  let statement_create_migration_state =
    "
    create table if not exists migration_state(
      k integer not null primary key,
      version integer not null
    )
    "
  use <- try_exec(statement_create_migration_state, on: conn)

  let current_version = case
    query(
      "select version from migration_state where k = 0",
      on: conn,
      with: [],
      expecting: dynamic.element(0, dynamic.int),
    )
  {
    Ok([first, ..]) -> first
    _ -> 0
  }

  list.index_map(migrations, fn(migration, i) { #(i, migration) })
  |> list.try_each(fn(state) {
    let #(i, migration) = state
    let version = i + 1
    case version > current_version {
      False -> Ok(Nil)
      _ -> {
        use <- try_exec(migration, on: conn)
        case
          query(
            "replace into migration_state (k, version) values(?, ?)",
            on: conn,
            with: [sqlight.int(0), sqlight.int(version)],
            expecting: decode_state(),
          )
        {
          Error(e) -> Error(e)
          _ -> Ok(Nil)
        }
      }
    }
  })
}

/// with_transaction have a function that maps a sqlite connection, similar to `wisp.mist_handler`
pub fn with_transaction(
  conn: sqlight.Connection,
  do: fn() -> Result(Nil, Error),
) -> Result(Nil, Error) {
  // can I better handle this?
  // map_error
  let assert Ok(_) = sqlight.exec("BEGIN TRANSACTION;", on: conn)
  case do() {
    Ok(_) -> {
      sqlight.exec("COMMIT", on: conn)
    }
    Error(_) -> {
      io.debug("rolling back")
      sqlight.exec("ROLLBACK", on: conn)
    }
  }
  |> result.map_error(SQLiteError)
}

/// exec
pub fn exec(
  sql: String,
  on connection: sqlight.Connection,
) -> Result(Nil, Error) {
  sqlight.exec(sql, on: connection)
  |> result.map_error(SQLiteError)
}

/// try_exec
pub fn try_exec(
  sql: String,
  on connection: sqlight.Connection,
  f f: fn() -> Result(Nil, Error),
) -> Result(Nil, Error) {
  case exec(sql, on: connection) {
    Ok(_) -> f()
    Error(e) -> Error(e)
  }
}

/// query
pub fn query(
  sql: String,
  on connection: sqlight.Connection,
  with arguments: List(sqlight.Value),
  expecting decoder: dynamic.Decoder(t),
) {
  sqlight.query(sql, on: connection, with: arguments, expecting: decoder)
  |> result.map_error(SQLiteError)
}

/// try_query
pub fn try_query(
  sql: String,
  on connection: sqlight.Connection,
  with arguments: List(sqlight.Value),
  expecting decoder: dynamic.Decoder(a),
  f f: fn(List(a)) -> Result(Nil, Error),
) -> Result(Nil, Error) {
  let rs = query(sql, on: connection, with: arguments, expecting: decoder)
  case rs {
    // get the first
    Ok(v) -> f(v)
    Error(e) -> Error(e)
  }
}

pub type State {
  State(k: Int, version: Int)
}

pub fn decode_state() {
  dynamic.decode2(
    State,
    dynamic.element(0, dynamic.int),
    dynamic.element(1, dynamic.int),
  )
}
