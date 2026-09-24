# pokegosu

To install the command line: `curl -fsSL https://pokegosu.com/install-cli.sh | sh`. See [apps/cli](apps/cli/README.md).

## Releasing

Pushing a version tag ships everything: the CD workflow migrates the database, deploys the Edge Functions and every web app, and publishes a GitHub release with the CLI's binaries once all of it is live.

1. In the Supabase dashboard, under Account → Access Tokens, create a token for project `iacgqcfqrciisaxxlmut` only, with Database read-write, Connection Pooling read, Project Settings read and Edge Functions read-write. A day's expiry is enough: it is used only by this release, and Supabase allows thirty days at most anyway.
2. `gh secret set SUPABASE_ACCESS_TOKEN --env production`, and paste it.
3. Tag `main` and push the tag: `git tag -a v0.2.0 -m v0.2.0 && git push origin v0.2.0`.

If the token was forgotten or has expired, the migrate job fails first and nothing ships. Set a fresh one and rerun the failed jobs.
