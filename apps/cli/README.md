# pokegosu command line

One binary for pokegosu's services, a word per service. A machine is enrolled once, with the account, and every service speaks with the key that enrolment leaves behind.

Today there is one service: `pokegosu coder`, which collects coding agent token usage from every machine you work on, into one account. It reads the logs your agent already writes, uploads hourly totals, and the web shows them.

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

For a deployment other than the default, give its address: `pokegosu auth login --url https://pokegosu.example.com`. The CLI reads `/.well-known/pokegosu.json` there to find the rest, so no backend address has to be known or typed.

Then let a scheduler run the sync. There is no daemon: one pass takes seconds.

```
*/15 * * * * /usr/local/bin/pokegosu coder sync --quiet
```

- A sync reports nothing from before this machine was enrolled. What the logs hold from earlier is nobody's business but this machine's, and a first run would otherwise upload months of history. `--since` asks for a different starting point, further back or less far.
- `pokegosu coder scan` prints what the parser found without sending anything. Run it first when a number looks wrong.
- Running `pokegosu auth login` again on an enrolled machine enrols it again with a new key. It keeps its id and history. That is also how a machine retired in the web comes back.
- A machine with no browser can be approved from anywhere: the code is all a person carries.

Settings live in `~/.config/pokegosu/config.json`, readable only by you; `POKEGOSU_CONFIG_HOME` puts them somewhere else. Each service keeps whatever else it needs beside them, such as coder's record of what it has already sent.

## Tests

| What                                       | How                                                |
| ------------------------------------------ | -------------------------------------------------- |
| Unit tests                                 | `moon run cli:test`                                |
| The parser, against the shared fixtures    | `moon run tests-coder:conformance-go`              |
| login and coder sync against a local stack | `moon run supabase:start`, then `moon run cli:e2e` |

The e2e suites make their own accounts and enrollment codes the way the web does, so nothing has to be set up by hand.
