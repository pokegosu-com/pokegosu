# PokeGosu Coder

Raise Pokémon with the tokens your coding agent spends.

PokeGosu Coder counts the tokens your coding agent uses on every machine you work on, and turns them into experience for your Pokémon. Work on a laptop, a server and a container, and it all goes to the same box. Claude Code is the agent it reads today.

## Getting started

Sign in at [pokegosu.com](https://pokegosu.com). Then, on each machine you code on, install the command line, enrol the machine in your account, and have Claude Code run the sync:

```sh
curl -fsSL https://pokegosu.com/install-cli.sh | sh
pokegosu auth login
pokegosu coder hook install claude-code
```

From then on, every Claude Code session on that machine reports as it goes, and [coder.pokegosu.com](https://coder.pokegosu.com) is where you play. To see what a machine would send without sending it, run `pokegosu coder scan`.

Other ways to install, and how to uninstall, are in the [command line's README](../cli/README.md).

## What leaves your machine

Only how many tokens were used, per hour and per agent. Your prompts, your code, file and project names, and the logs themselves stay on the machine.

Token counts are read from your agent's own logs and can differ from what your provider bills.
