# PokeGosu Coder

Raise Pokémon with the tokens your coding agent spends.

PokeGosu Coder counts the tokens your coding agent uses on every machine you work on, and turns them into experience for your Pokémon. Work on a laptop, a server and a container, and it all goes to the same box. It reads Claude Code and Codex.

The hours you code earn points too. You earn some yourself, and Pokémon of Lv.50 and up earn more on requests from other Pokémon, the more the better their types would hit the one asking. Points buy evolution stones and regional eggs in the shop.

## Getting started

Sign in at [pokegosu.com](https://pokegosu.com). Then, on each machine you code on, install the command line, enrol the machine in your account, and have your agent run the sync:

```sh
curl -fsSL https://pokegosu.com/install-cli.sh | sh
pokegosu auth login
pokegosu coder hook install claude-code   # or codex, or both
```

From then on, every session on that machine reports as it goes, and [coder.pokegosu.com](https://coder.pokegosu.com) is where you play. Codex asks you to trust its hooks the next time it starts; they run once you do. To see what a machine would send without sending it, run `pokegosu coder scan`.

Other ways to install, and how to uninstall, are in the [command line's README](../cli/README.md).

## What leaves your machine

Only how many tokens were used, per hour and per agent. Your prompts, your code, file and project names, and the logs themselves stay on the machine.

Token counts are read from your agent's own logs and can differ from what your provider bills.
