#!/bin/sh
# Installs the pokegosu command line from a GitHub release:
#
#   curl -fsSL https://pokegosu.com/install-cli.sh | sh
#
# It picks the build for this machine, checks it against the release's
# checksums, and puts it in ~/.local/bin, so no sudo is needed. Running it
# again installs the newest release over the old one.
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

  version="${POKEGOSU_VERSION:-}"
  if [ -n "$version" ]; then
    base="https://github.com/$repo/releases/download/$version"
  else
    base="https://github.com/$repo/releases/latest/download"
  fi

  dir="${POKEGOSU_INSTALL_DIR:-$HOME/.local/bin}"
  name="pokegosu_${os}_${arch}.tar.gz"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  echo "downloading ${version:-the newest release} for $os/$arch"
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

  echo
  echo 'next: pokegosu auth login'
}

fail() {
  echo "pokegosu: $1" >&2
  exit 1
}

main "$@"
