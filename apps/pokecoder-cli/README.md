# pokecoder CLI

Collects coding agent token usage from every machine you work on, into one account. It reads the logs your agent already writes, uploads hourly totals, and the web shows them.

## Using it

Open pokecoder on the web, choose "add a machine", then run this on the machine and type in the code it shows:

```sh
pokecoder login
```

That enrols with the default service, `https://coder.pokegosu.com`. For any other deployment, give the address you sign in at; the web's "add a machine" page shows the command with it filled in:

```sh
pokecoder login --url https://coder.example.com
```

`login` asks that address where its API is (`/.well-known/pokecoder.json`), so the backend's own address never needs to be known or typed.

Then let a scheduler run it. There is no daemon: one pass takes seconds.

```
*/15 * * * * /usr/local/bin/pokecoder sync --quiet
```

- `pokecoder scan` prints what the parser found without sending anything. Run it first when a number looks wrong.
- Each machine gets its own key by trading in the code; nothing secret is typed or pasted.
- Running `login` again on an enrolled machine enrols it again with a new key. It keeps its id and history. That is also how a machine retired in the web comes back.

## Tests

| What                                    | How                                                          |
| --------------------------------------- | ------------------------------------------------------------ |
| Unit tests                              | `moon run pokecoder-cli:test`                                |
| The parser, against the shared fixtures | `moon run tests-tokenusage:conformance-go`                   |
| login and sync against a local stack    | `moon run supabase:start`, then `moon run pokecoder-cli:e2e` |

The e2e suites make their own accounts and enrollment codes the way the web does, so nothing has to be set up by hand.
