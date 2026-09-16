///|
/// Everything the tool does lives in the library, so it can be tested without
/// a process around it. This entry point only supplies the real environment:
/// the command line, the two streams, and the network call behind `--ai`.
async fn main {
  let args = @env.args()
  // `args` carries the program name first; the parser wants only the rest.
  let rest = if args.length() > 0 { args[1:].to_owned() } else { [] }
  let result = @lib.run(rest, analyze=@lib.analyze)
  if result.out.length() > 0 {
    @stdio.stdout.write(result.out)
  }
  if result.err.length() > 0 {
    @stdio.stderr.write(result.err)
  }
  @sys.exit(result.code)
}
