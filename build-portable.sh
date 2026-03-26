#!/bin/bash
# claude-portable-musl バンドルをビルドするスクリプト
#
# 前提条件:
#   - Node.js 22+ と npm
#   - @anthropic-ai/claude-code がグローバルインストール済み
#   - Docker（musl libc抽出用）
#   - rsync
#
# 使い方:
#   ./build-portable.sh
#   ./build-portable.sh --node-version v22.14.0 --output ./dist

set -euo pipefail

NODE_VERSION="${1:-v22.14.0}"
OUTPUT_DIR="${2:-.}"
WORK_DIR=$(mktemp -d)
DEST="$WORK_DIR/claude-portable-musl"

echo "=== claude-portable-musl builder ==="
echo "Node.js version: $NODE_VERSION"
echo "Working dir: $WORK_DIR"

# Claude Code のインストール先を検出
CLAUDE_SRC="$(npm root -g)/@anthropic-ai/claude-code"
if [ ! -d "$CLAUDE_SRC" ]; then
    echo "Error: @anthropic-ai/claude-code not found at $CLAUDE_SRC"
    echo "Run: npm install -g @anthropic-ai/claude-code"
    exit 1
fi
CLAUDE_VERSION=$(node -e "console.log(require('$CLAUDE_SRC/package.json').version)")
echo "Claude Code version: $CLAUDE_VERSION"

# 1. musl版 Node.js ダウンロード
echo ""
echo "[1/5] Downloading musl Node.js $NODE_VERSION..."
curl -sL "https://unofficial-builds.nodejs.org/download/release/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64-musl.tar.gz" \
    -o "$WORK_DIR/node-musl.tar.gz"
cd "$WORK_DIR" && tar xzf node-musl.tar.gz

# 2. musl ランタイムライブラリ抽出
echo "[2/5] Extracting musl libs from Alpine..."
mkdir -p "$WORK_DIR/musl-libs"
docker run --rm -v "$WORK_DIR/musl-libs:/out" alpine:latest sh -c '
    apk add --no-cache libstdc++ >/dev/null 2>&1
    cp /lib/ld-musl-x86_64.so.1 /out/
    cp /usr/lib/libstdc++.so.6 /out/
    cp /usr/lib/libgcc_s.so.1 /out/
'

# 3. バンドル構築
echo "[3/5] Building bundle..."
mkdir -p "$DEST/lib/deps"

cp "$WORK_DIR/node-${NODE_VERSION}-linux-x64-musl/bin/node" "$DEST/"

cp "$WORK_DIR/musl-libs/ld-musl-x86_64.so.1" "$DEST/lib/deps/"
cp "$WORK_DIR/musl-libs/libstdc++.so.6" "$DEST/lib/deps/"
cp "$WORK_DIR/musl-libs/libgcc_s.so.1" "$DEST/lib/deps/"
chmod +x "$DEST/lib/deps/ld-musl-x86_64.so.1"

rsync -a \
    --exclude='*/arm64-*' \
    --exclude='*/x64-darwin*' \
    --exclude='*/x64-win32*' \
    --exclude='*/arm64-darwin*' \
    --exclude='*/arm64-win32*' \
    "$CLAUDE_SRC" "$DEST/lib/"

# 4. 起動スクリプト
echo "[4/5] Creating launcher..."
cat > "$DEST/claude" << 'SCRIPT'
#!/bin/sh
DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
export LD_LIBRARY_PATH="$DIR/lib/deps${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CLAUDE_CONFIG_DIR="$DIR/config"
export CLAUDE_CODE_TMPDIR="$DIR/tmp"
mkdir -p "$DIR/config" "$DIR/tmp"
exec "$DIR/lib/deps/ld-musl-x86_64.so.1" "$DIR/node" "$DIR/lib/claude-code/cli.js" "$@"
SCRIPT
chmod +x "$DEST/claude"

# 5. アーカイブ作成
echo "[5/5] Creating archive..."
cd "$WORK_DIR"
ARCHIVE_NAME="claude-portable-musl-${CLAUDE_VERSION}.tar.gz"
tar czf "$ARCHIVE_NAME" claude-portable-musl/
cp "$ARCHIVE_NAME" "$OUTPUT_DIR/"

# クリーンアップ
rm -rf "$WORK_DIR"

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_DIR/$ARCHIVE_NAME"
echo "Size: $(du -h "$OUTPUT_DIR/$ARCHIVE_NAME" | cut -f1)"
echo ""
echo "Deploy:"
echo "  scp $OUTPUT_DIR/$ARCHIVE_NAME user@target:~/"
echo "  ssh user@target 'tar xzf $ARCHIVE_NAME && ~/claude-portable-musl/claude'"
