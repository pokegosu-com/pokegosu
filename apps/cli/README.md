# pokegosu command line

One binary for pokegosu's services, a word per service. Today there is one: `pokegosu coder`, which collects coding agent token usage from every machine you work on, into one account. It reads the logs your agent already writes, uploads hourly totals, and the web shows them.

## Using it

Open coder on the web, choose "add a machine", then run this on the machine and type in the code it shows:

```sh
pokegosu coder login
```

That enrols with the default service, `https://coder.pokegosu.com`. For any other deployment, give the address you sign in at; the web's "add a machine" page shows the command with it filled in:

```sh
pokegosu coder login --url https://coder.example.com
```

`pokegosu coder login` asks that address where its API is (`/.well-known/coder.json`), so the backend's own address never needs to be known or typed.

Then let a scheduler run it. There is no daemon: one pass takes seconds.

```
*/15 * * * * /usr/local/bin/pokegosu coder sync --quiet
```

- `pokegosu coder scan` prints what the parser found without sending anything. Run it first when a number looks wrong.
- Each machine gets its own key by trading in the code; nothing secret is typed or pasted.
- Running `pokegosu coder login` again on an enrolled machine enrols it again with a new key. It keeps its id and history. That is also how a machine retired in the web comes back.

## Tests

| What                                    | How                                                |
| --------------------------------------- | -------------------------------------------------- |
| Unit tests                              | `moon run cli:test`                                |
| The parser, against the shared fixtures | `moon run tests-coder:conformance-go`              |
| login and sync against a local stack    | `moon run supabase:start`, then `moon run cli:e2e` |

The e2e suites make their own accounts and enrollment codes the way the web does, so nothing has to be set up by hand.
