# Contributing to PokeGosu

This is how to set up PokeGosu, find your way around it, and ship a change.

## Installation

Everything runs through moon, so there is little to install by hand: moon and Docker. moon installs the Node, pnpm and Go versions pinned in `.moon/toolchains.yaml`.

```sh
moon setup                     # the toolchain and dependencies
moon run supabase:start        # the local database and auth, in Docker
moon run coder-web:dev         # an app
```

Each web app reads `.env.local`, copied from its `.env.example`; `moon run supabase:status` prints the local values.

## Design

PokeGosu is designed to run on Cloudflare Workers and Supabase, so it has no servers of its own to run or maintain.

- **Cloudflare Workers** serve the web apps, each as a Worker of its own.
- **Supabase** provides the Postgres database, sign-in and Edge Functions. One sign-in works for every app.

## Deploy

A deploy ships everything together: the database first, then the rest. It needs a Supabase project, a Cloudflare account and a domain.

**Supabase** holds the database, sign-in and the Edge Functions. Create the project with _Automatically expose new tables_ turned off. Set the sign-in site URL and redirect to the account app, and give it SMTP to send mail from your domain. The migrations and functions are pushed with the Supabase CLI.

**Cloudflare** serves the apps, one Worker each, built with production values. The first time, a Worker has no address: attach its hostname in the dashboard.

The apps build with these values:

| Variable                               | What it is                                   |
| -------------------------------------- | -------------------------------------------- |
| `CLOUDFLARE_API_TOKEN`                 | A token that can edit Workers on the account |
| `CLOUDFLARE_ACCOUNT_ID`                | The account the Workers live in              |
| `NEXT_PUBLIC_SUPABASE_URL`             | The Supabase project's URL                   |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | The project's publishable key                |
| `NEXT_PUBLIC_ACCOUNT_URL`              | The account app's address                    |
| `NEXT_PUBLIC_POKEDEX_URL`              | The Pokédex app's address                    |
| `NEXT_PUBLIC_COOKIE_DOMAIN`            | `.<domain>`, so every app shares one sign-in |

## Directory structure

The repository holds every app and everything they share, and all of it ships together.

- `apps/`: one directory per app
  - `landing-web/`: the front page
  - `account-web/`: sign-in, and the machines enrolled in an account
  - `pokedex-web/`: the Pokédex, and the Pokémon information every app uses
  - `coder-web/`: coding agent token usage, and the box
  - `cli/`: the `pokegosu` command line
- `libs/`: code the apps share
  - `go/`
    - `auth/`: enrolling a machine, and its API key
    - `coder/`: reading agent logs into hourly totals, and uploading them
  - `ts/`
    - `config/`: shared TypeScript config, and the build version
    - `supabase/`: Supabase clients, and validating their settings
    - `ui/`: the shared theme and components
- `supabase/`: the backend
  - `migrations/`: the database schema and its data
  - `functions/`: Edge Functions, for requests from outside the browser such as the command line
- `tests/`: cases shared by every language that implements the same thing

## Rules

A few rules keep production and every client in step.

- A migration is never edited. To change the database, add a new one.
- Where the same thing is implemented in more than one language, each language has a small driver in `tests/`, and every driver passes the same cases.
