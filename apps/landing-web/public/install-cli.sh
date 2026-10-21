#!/bin/sh
# Installs the pokegosu command line from a GitHub release:
#
#   curl -fsSL https://pokegosu.com/install-cli.sh | sh
#
# It asks which pokegosu is installed and which release is the newest, and
# downloads only when they differ. It picks the build for this machine, checks
# it against the release's checksums, and puts it in ~/.local/bin, so no sudo
# is needed. Running it again updates pokegosu in place.
#
#   POKEGOSU_VERSION      a release tag such as v0.2.0, instead of the newest
#   POKEGOSU_INSTALL_DIR  where the binary goes, instead of ~/.local/bin
#
# Everything is inside main, so a download cut short runs nothing.

set -eu

repo='pokegosu-com/pokegosu'

main() {
  case "$(uname -s)" in
    Linux) os='linux' ;;
    Darwin) os='darwin' ;;
    *) fail "no build for $(uname -s); build from source instead" ;;
  esac

  case "$(uname -m)" in
    x86_64 | amd64) arch='amd64' ;;
    arm64 | aarch64) arch='arm64' ;;
    *) fail "no build for $(uname -m); build from source instead" ;;
  esac

  dir="${POKEGOSU_INSTALL_DIR:-$HOME/.local/bin}"
  name="pokegosu_${os}_${arch}.tar.gz"

  # A binary that will not run, such as one for another machine, counts as
  # none, so it is replaced.
  current=''
  if [ -x "$dir/pokegosu" ]; then
    current="$("$dir/pokegosu" version 2> /dev/null)" || current=''
  fi

  version="${POKEGOSU_VERSION:-}"
  if [ -z "$version" ]; then
    version="$(latest)" || fail 'could not find the newest release on GitHub'
  fi

  if [ "$current" = "$version" ]; then
    echo "pokegosu $version is already installed in $dir"
    exit 0
  fi

  # Downloaded by tag rather than from releases/latest, so the binary and its
  # checksums come from the same release even if a new one lands meanwhile.
  base="https://github.com/$repo/releases/download/$version"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  if [ -n "$current" ]; then
    echo "updating pokegosu from $current to $version for $os/$arch"
  else
    echo "installing pokegosu $version for $os/$arch"
  fi
  curl -fsSL -o "$tmp/$name" "$base/$name"
  curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"

  (
    cd "$tmp"
    grep " $name\$" checksums.txt > expected
    if command -v sha256sum > /dev/null; then
      sha256sum -c --status expected
    else
      shasum -a 256 -c --status expected
    fi
  ) || fail "$name does not match the release's checksums"

  tar -xzf "$tmp/$name" -C "$tmp"
  mkdir -p "$dir"
  # Moved into place rather than written over, so a pokegosu that is running,
  # such as a sync, keeps the file it started with.
  cp "$tmp/pokegosu" "$dir/.pokegosu.new"
  chmod 755 "$dir/.pokegosu.new"
  mv "$dir/.pokegosu.new" "$dir/pokegosu"

  echo "installed $("$dir/pokegosu" version) to $dir/pokegosu"

  case ":$PATH:" in
    *":$dir:"*) ;;
    *) echo "$dir is not on your PATH; add it in your shell's profile" ;;
  esac

  # An update keeps the machine's login, so only a new install needs one.
  if [ -z "$current" ]; then
    echo
    echo 'next: pokegosu auth login'
  fi
}

# The newest release's tag, from where github.com/<repo>/releases/latest
# redirects. The API would say the same but limits calls without a token.
latest() {
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")"
  tag="${url##*/tag/}"
  [ "$tag" != "$url" ] && [ -n "$tag" ] || return 1
  echo "$tag"
}

fail() {
  echo "pokegosu: $1" >&2
  exit 1
}

main "$@"
