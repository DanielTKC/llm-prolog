# llm-prolog

A small Prolog oracle for Express route specs. You describe routes as data,
and Prolog generates the router code, lints the spec, suggests security
hardening, and can explain any line of its output by walking the rules that
produced it.

It plugs into Claude Code two ways: a post-write hook that rejects a spec the
linter flags, and an MCP server the agent can ask questions mid-task.

## Dependencies

- SWI-Prolog 9 or newer (developed on 10.0.2)
- Python 3 (only the hook uses it, and macOS ships one)

On macOS with Homebrew:

```sh
brew install swi-prolog
swipl --version
```

## Running it

Generate code, lint, and suggest for a spec file:

```sh
swipl driver.pl examples/routes.json
```

The exit code is the verdict. `0` means the spec is clean, `1` means the linter
raised warnings, `2` means the spec never loaded. Add `--json` for a
machine-readable report:

```sh
swipl driver.pl --json examples/routes.json
```

Run the tests:

```sh
swipl tests.plt
```

## Spec format

A JSON file with a `routes` array. Each route has a name, method, path, and a
list of features. Features are plain strings, or a single-key object when the
feature takes an argument:

```json
{
  "routes": [
    {"name": "users_list",  "method": "get",  "path": "/users", "features": ["auth", "paginated"]},
    {"name": "user_create", "method": "post", "path": "/users", "features": ["auth", {"validated": "user_schema"}, "csrf"]}
  ]
}
```

See `examples/` for more.

## Asking why

Inside `swipl`, `why/2` returns the derivation behind a generated route, a
warning, or a suggestion:

```prolog
?- use_module(express_patterns).
?- load_routes_json('examples/routes.json').
?- why(users_list, Steps).
?- why(warning(missing_validation, upload_avatar), Steps).
?- why(suggestion(add_rate_limit, login), Steps).
```

It fails for anything the rules cannot prove, so an explanation only exists
where the finding actually holds.

## Claude Code integration

Both pieces are configured in the repo and work as soon as you open the
project in Claude Code.

**Hook.** `.claude/settings.json` registers `.claude/hooks/lint-spec.sh` as a
PostToolUse hook. After any Write or Edit to a file under `examples/*.json`,
it runs the driver. A non-zero exit blocks the edit and feeds the report back
to the model.

**MCP server.** `.mcp.json` registers `mcp_server.pl` as a stdio server named
`prolog-oracle` with four tools: `generate`, `lint`, `suggest`, and `why`.
Each takes the routes inline. You can also start it by hand and speak
JSON-RPC to it one line at a time:

```sh
swipl mcp_server.pl
```

## Layout

| File | What it is |
|------|-----------|
| `express_patterns.pl` | The rules: routes, middleware, generation, lint, suggest, why |
| `driver.pl` | Command-line front end with the exit-code verdict |
| `mcp_server.pl` | JSON-RPC stdio server exposing the rules as MCP tools |
| `tests.plt` | plunit test suite |
| `examples/` | Sample specs, including one that is clean and one that is not |
| `.claude/hooks/lint-spec.sh` | The post-write gate |
