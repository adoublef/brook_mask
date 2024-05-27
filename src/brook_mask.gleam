// gleam
import gleam/erlang/process
import gleam/io

// glint
import argv
import glint

// wisp
import mist
import wisp

// me
import net/http

fn port_flag() -> glint.Flag(Int) {
  glint.int_flag("port")
  |> glint.flag_default(8000)
  |> glint.flag_help("http listening port")
}

fn dsn_flag() {
  glint.string_flag("dsn")
  |> glint.flag_default("local.db")
  |> glint.flag_help("database source name")
}

fn serve() -> glint.Command(Nil) {
  //  add constraints
  //  use <- glint.command_help("some helpful text")
  //  use <- glint.unnamed_args(glint.EqArgs(0))
  use _, _, flags <- glint.command()
  let assert Ok(port) = glint.get_flag(flags, port_flag())
  let assert Ok(dsn) = glint.get_flag(flags, dsn_flag())
  //  let assert [name, ..rest] = args
  io.debug(dsn)
  io.debug(port)
  // This sets the logger to print INFO level logs, and other sensible defaults
  // for a web application.
  wisp.configure_logger()

  // Here we generate a secret key, but in a real application you would want to
  // load this from somewhere so that it is not regenerated on every restart.
  // use env_var for this
  let secret_key_base = wisp.random_string(64)

  // Start the Mist web server.
  let assert Ok(_) =
    wisp.mist_handler(http.handle, secret_key_base)
    |> mist.new
    |> mist.port(port)
    |> mist.start_http

  // The web server runs in new Erlang process, so put this one to sleep while
  // it works concurrently.
  process.sleep_forever()
}

fn migrate() -> glint.Command(Nil) {
  // use <- glint.command_help("some helpful text")
  // use <- glint.unnamed_args(glint.MinArgs(1))
  use _, _, flags <- glint.command()
  let assert Ok(_) = glint.get_flag(flags, dsn_flag())
  Nil
}

fn run() {
  glint.new()
  |> glint.group_flag([], port_flag())
  |> glint.group_flag([], dsn_flag())
  |> glint.add(at: [], do: serve())
  |> glint.add(at: ["serve"], do: serve())
  |> glint.add(at: ["migrate"], do: migrate())
}

pub fn main() {
  // io.println is the command output
  // 
  glint.run_and_handle(run(), argv.load().arguments, io.debug)
}
