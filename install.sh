#!/bin/sh
set -e
VERSION="v2.1.81"
URL="https://github.com/yamanongs/claude-portable/releases/download/${VERSION}/claude-portable-musl.tar.gz"
curl -fsSL "$URL" | tar xz
echo "Done. Run: ./claude-portable-musl/claude"
