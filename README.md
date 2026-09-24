# pokegosu

To install the command line: `curl -fsSL https://pokegosu.com/install-cli.sh | sh`. See [apps/cli](apps/cli/README.md).

## Releasing

Pushing a version tag ships everything: the CD workflow migrates the database, deploys the Edge Functions and every web app, and publishes a GitHub release with the CLI's binaries once all of it is live.

1. Create a Supabase access token scoped to the production project only, with Database read-write, Connection Pooling read, Project Settings read and Edge Functions read-write. It is used only by this release, so a short expiry is enough; Supabase allows thirty days at most.
2. Set it as the `SUPABASE_ACCESS_TOKEN` secret of the `production` environment: `gh secret set SUPABASE_ACCESS_TOKEN --env production`.
3. Tag `main` with the version and push the tag: `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.

If the token is missing or has expired, the migrate job fails first and nothing ships. Set a fresh one and rerun the failed jobs.
