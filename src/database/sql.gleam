// gleam
import gleam/bool
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string

// filepath
import filepath

// simplifile
import simplifile

// sqlight
import sqlight

pub type Connection {
  Connection(conn: sqlight.Connection, txlock: TxLock)
}

/// open creates a single connection to a sqlite file
pub fn open(path: String) -> Result(Connection, Error) {
  use conn <- result.try(
    sqlight.open(path)
    |> result.map_error(SQLError),
  )
  let conn = Connection(conn, BeginImmediate)
  [
    #("journal_mode", "wal"),
    #("busy_timeout", "5000"),
    #("synchronous", "normal"),
    #("cache_size", "1000000000"),
    #("foreign_keys", "on"),
    #("temp_store", "memory"),
    #("mmap_size", "3000000000"),
  ]
  |> list.try_map(fn(pragma) {
    exec("pragma " <> pragma.0 <> "=" <> pragma.1, on: conn)
  })
  |> result.replace(conn)
}

pub fn close(conn: Connection) -> Result(Nil, Error) {
  sqlight.close(conn.conn)
  |> result.map_error(SQLError)
}

pub fn with_connection(path: String, f: fn(Connection) -> a) -> a {
  let assert Ok(conn) = open(path)
  let value = f(conn)
  let assert Ok(_) = close(conn)
  value
}

/// to_connection wraps the sqlight instance
pub fn to_connection(conn: sqlight.Connection) -> Connection {
  Connection(conn: conn, txlock: Begin)
}

pub type TxLock {
  Begin
  BeginImmediate
  BeginExclusive
}

pub fn txlock_to_string(txlock: TxLock) -> String {
  case txlock {
    Begin -> "BEGIN"
    BeginImmediate -> "BEGIN IMMEDIATE"
    BeginExclusive -> "BEGIN EXCLUSIVE"
  }
}

pub type Error {
  FileError(simplifile.FileError)
  FormatError(filename: String)
  SQLError(sqlight.Error)
}

pub fn describe_error(error: Error) -> String {
  case error {
    FileError(e) -> simplifile.describe_error(e)
    FormatError(filename) -> "invalid format for file: " <> filename
    SQLError(e) -> e.message
  }
}

pub type Direction {
  Up
  Down
}

pub type File {
  File(version: Int, content: String)
}

pub type Migration {
  /// Migration is a file
  Migration(t: Direction, file: File)
}

fn parse_direction(path: String) -> Result(#(Int, Direction), Error) {
  let path = filepath.base_name(path)
  case string.split(path, ".") {
    [version, "up", ..] -> {
      case int.parse(version) {
        Ok(version) -> Ok(#(version, Up))
        _ -> Error(FormatError(path))
      }
    }
    [version, "down", ..] -> {
      case int.parse(version) {
        Ok(version) -> Ok(#(version, Down))
        _ -> Error(FormatError(path))
      }
    }
    _ -> Error(FormatError(path))
  }
}

fn get_files(in directory: String) -> Result(List(String), Error) {
  simplifile.get_files(directory)
  |> result.map_error(FileError)
}

fn read(from filepath: String) -> Result(String, Error) {
  simplifile.read(filepath)
  |> result.map_error(FileError)
}

/// read_migrations reads from a directory and returns a list of 
/// migrations paried with the filename
pub fn read_migrations(in directory: String) -> Result(List(Migration), Error) {
  // fully qualifiyed name
  use files <- result.try(get_files(directory))
  use file <- list.try_map(
    files
    |> list.sort(string.compare),
  )
  use #(version, direction) <- result.try(parse_direction(file))
  // parse the file name and check it has the direction in the name
  use content <- result.try(read(file))
  Ok(Migration(t: direction, file: File(version: version, content: content)))
}

pub fn exec(sql: String, on connection: Connection) -> Result(Nil, Error) {
  let Connection(conn, _) = connection
  sqlight.exec(sql, on: conn)
  |> result.map_error(SQLError)
}

pub fn query(
  sql: String,
  on connection: Connection,
  with arguments: List(sqlight.Value),
  expecting decoder: dynamic.Decoder(t),
) {
  let Connection(conn, _) = connection
  sqlight.query(sql, on: conn, with: arguments, expecting: decoder)
  |> result.map_error(SQLError)
}

pub fn with_transaction(
  conn: Connection,
  do: fn() -> Result(Nil, Error),
) -> Result(Nil, Error) {
  use _ <- result.try(exec(txlock_to_string(conn.txlock), on: conn))
  case do() {
    Ok(_) -> {
      exec("COMMIT", conn)
    }
    Error(e) -> {
      use _ <- result.try(exec("ROLLBACK", conn))
      Error(e)
    }
  }
}

/// exec_migrations reads from the migration directory and attempts to run them.
pub fn exec_migrations(
  from directory: String,
  on conn: Connection,
) -> Result(Nil, Error) {
  // no point carrying on from this point
  let assert Ok(migrations) = read_migrations(directory)
  use <- with_transaction(conn)
  let statement_create_migration_state =
    "
    create table if not exists migration_state(
      k integer not null primary key,
      version integer not null
    )
    "
  use _ <- result.try(exec(statement_create_migration_state, on: conn))
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
  list.try_map(migrations, fn(migration) {
    let Migration(t, File(version, migration)) = migration
    let version = version + 1
    use <- bool.guard(
      when: !{ t == Up && version > current_version },
      return: Ok(Nil),
    )
    use _ <- result.try(exec(migration, on: conn))
    case
      query(
        "replace into migration_state (k, version) values(?, ?)",
        on: conn,
        with: [sqlight.int(0), sqlight.int(version)],
        expecting: dynamic.decode2(
          State,
          dynamic.element(0, dynamic.int),
          dynamic.element(1, dynamic.int),
        ),
      )
    {
      Error(e) -> Error(e)
      _ -> Ok(Nil)
    }
  })
  |> result.replace(Nil)
}

type State {
  State(k: Int, version: Int)
}
