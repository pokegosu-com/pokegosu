# pokegosu command line

One binary for pokegosu's services, a word per service. A machine is enrolled once, with the account, and every service speaks with the key that enrolment leaves behind.

Today there is one service: `pokegosu coder`, which collects coding agent token usage from every machine you work on, into one account. It reads the logs your agent already writes, uploads hourly totals, and the web shows them.

## Installing

On Linux or macOS, amd64 or arm64:

```sh
curl -fsSL https://pokegosu.com/install-cli.sh | sh
```

The script picks the build for this machine from the newest GitHub release, checks it against the release's `checksums.txt`, and puts it in `~/.local/bin`, so no sudo is needed. It says so when that directory is not on your `PATH`. `POKEGOSU_VERSION=v0.2.0` installs a given release instead, and `POKEGOSU_INSTALL_DIR` puts the binary somewhere else. Running it again updates `pokegosu` in place. [Read the script](https://pokegosu.com/install-cli.sh) before you pipe it to `sh`, if you like.

To do it by hand, download `pokegosu_<os>_<arch>.tar.gz` from a [release](https://github.com/pokegosu-com/pokegosu/releases), check it against `checksums.txt`, and put the `pokegosu` inside it on your `PATH`.

From source, with Go 1.24:

```sh
go install github.com/pokegosu-com/pokegosu/apps/cli/cmd/pokegosu@latest
```

That build says `dev` for its version, since the version is written in only when the release is built.

To uninstall, run `pokegosu coder hook uninstall claude-code codex` and `pokegosu auth logout`, which retires the machine so its key stops working, then delete the binary, and `~/.config/pokegosu` with it.

## Using it

Run this on the machine:

```sh
pokegosu auth login
```

It shows a code and an address. Open that address, signed in, check that the code matches the one on the machine, and approve it. The machine collects its own key and is enrolled.

```
open https://account.pokegosu.com/devices/add/XPTQ-4F2K
and approve this machine. The code is XPTQ-4F2K.

waiting for approval… approved
enrolled "laptop" with https://pokegosu.com
```

Nothing secret is typed or pasted. The code is worth little — ten minutes, one use, and only a signed-in person can approve it — and the key is handed to the machine that asked, never through the browser.

`pokegosu auth logout` retires this machine in the account, as deleting it in the web does, and deletes its settings. Its key stops working, and the usage it sent stays in the account. Retiring is final: a login afterwards enrols this machine as a new machine. If the server cannot be reached, the settings are kept, since the key may still work.

For a deployment other than the default, give its address: `pokegosu auth login --url https://pokegosu.example.com`. The CLI reads `/.well-known/pokegosu.json` there to find the rest, so no backend address has to be known or typed.

Then have your coding agent run the sync:

```sh
pokegosu coder hook install claude-code   # and/or codex
```

That adds hooks to Claude Code's user settings (`~/.claude/settings.json`, or under `CLAUDE_CONFIG_DIR`), and changes nothing else there:

```sh
# when a session ends
pokegosu coder sync --jsonl --no-fail >> ~/.config/pokegosu/hook.claude-code.jsonl
# each time Claude finishes answering, in the background
pokegosu coder sync --jsonl --no-fail --min-interval 15m >> ~/.config/pokegosu/hook.claude-code.jsonl
```

So an open session reports every fifteen minutes or so, and a closing one reports what is left. The agent is what writes the logs, so the sync runs wherever it does — a laptop, a server, a container with no cron or systemd — and when no agent is running there is nothing new to send. `--no-fail` keeps a failed sync from interrupting the session; `--jsonl` prints how each sync went as a line of JSON, which the hook appends to its log. The hooks run this binary by its full path, so after moving it, install them again.

`pokegosu coder hook install codex` adds the same two hooks to Codex's user hooks (`~/.codex/hooks.json`, or under `CODEX_HOME`), logging to `hook.codex.jsonl`. Two things differ. Codex runs a hook from that file only once you trust it, and asks the next time it starts; until you do, the hooks do not run. And Codex gives a closing session's hooks three seconds at most, so that hook starts the sync in the background and returns, and the sync finishes after Codex has gone.

| Command                                 | Does                                                                                                                                     |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `pokegosu coder hook install <agent>`   | Adds the hooks, or replaces them                                                                                                         |
| `pokegosu coder hook uninstall <agent>` | Removes the hooks, and nothing else                                                                                                      |
| `pokegosu coder hook logs <agent>`      | The syncs the hooks ran, and how each went (`-n` for more)                                                                               |
| `pokegosu coder hook doctor`            | Checks the folder the hooks log to is there, and each event has a hook that runs a binary that is still there; says how to fix it if not |

- A sync reports nothing from before this machine was enrolled. What the logs hold from earlier is nobody's business but this machine's, and the server ignores those hours whoever sends them.
- A sync reads every agent it knows: Claude Code (`~/.claude/projects`, or under `CLAUDE_CONFIG_DIR`) and Codex (`~/.codex/sessions` and `archived_sessions`, or under `CODEX_HOME`). Whichever agent's hook runs a sync, it sends both.
- `pokegosu coder scan` prints what the parser found without sending anything. Run it first when a number looks wrong. `--path` reads another directory instead, and needs `--provider claude_code` or `--provider codex` to say whose logs it holds.
- A machine is enrolled once. Its id lives in the settings, so a machine that was deleted, or that lost its key, enrols as a new machine after `pokegosu auth logout`, and the old one keeps the history it earned.
- A machine with no browser can be approved from anywhere: the code is all a person carries.

`pokegosu completion <shell>` prints a completion script for bash, zsh, fish or PowerShell; `pokegosu completion zsh --help` says where to put it.

Settings live in `~/.config/pokegosu/config.json`, readable only by you; `POKEGOSU_CONFIG_HOME` puts them somewhere else. Each service keeps whatever else it needs beside them, such as coder's record of what it has already sent.

## Tests

| What                                  | How                                                      |
| ------------------------------------- | -------------------------------------------------------- |
| Unit tests                            | `moon run cli:test`                                      |
| The libraries it is built from        | `moon run go-auth:test go-coder:test`                    |
| The parsers, against the shared cases | `moon run coder-scan-claude-code:go coder-scan-codex:go` |
