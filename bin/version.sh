#!/usr/bin/env bash
: <<DOCXX
 version.sh

 Derives version metadata from Git or environment.
 Never mutates source files.

Author: morgan@morganism.dev
Date: Fri 30 Jan 2026 05:58:51 GMT

Usage:
include version.sh
echo "$VERSION $COMMIT $AUTHOR"

DOCXX

__GIT_COMMIT() {
  git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

__GIT_TAG() {
  git describe --tags --dirty --always 2>/dev/null || echo "unreleased"
}

__GIT_DATE() {
  git show -s --format=%cs HEAD 2>/dev/null || echo "unknown"
}

__GIT_AUTHOR() {
  git show -s --format='%an <%ae>' HEAD 2>/dev/null || echo "unknown"
}

# Allow CI to override everything
VERSION="${VERSION:-$(__GIT_TAG)}"
COMMIT="${COMMIT:-$(__GIT_COMMIT)}"
BUILD_DATE="${BUILD_DATE:-$(__GIT_DATE)}"
AUTHOR="${AUTHOR:-$(__GIT_AUTHOR)}"


