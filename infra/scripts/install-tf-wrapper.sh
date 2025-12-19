#!/usr/bin/env bash
# tfラッパーのインストール

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly WRAPPER_SCRIPT="$SCRIPT_DIR/tf"
readonly USER_BIN="$HOME/.local/bin"
readonly LINK_PATH="$USER_BIN/tf"

# カラー定義
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

# ~/.local/binディレクトリを作成
mkdir -p "$USER_BIN"

# 既存のリンクがある場合は削除
if [[ -L $LINK_PATH ]]; then
  info "既存のリンクを削除: $LINK_PATH"
  rm "$LINK_PATH"
fi

# シンボリックリンク作成
ln -s "$WRAPPER_SCRIPT" "$LINK_PATH"
success "tfコマンドをインストールしました: $LINK_PATH"

# PATHの確認
if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
  warn "$HOME/.local/bin がPATHに含まれていません"
  info "以下のコマンドでPATHに追加してください:"
  # shellcheck disable=SC2016
  echo 'export PATH="$HOME/.local/bin:$PATH"'
  echo ""
  info "または、fishシェルを使用している場合:"
  echo "fish_add_path ~/.local/bin"
fi

success "インストール完了！"
info "使用方法:"
echo "  tf init"
echo "  tf plan"
echo "  tf apply"
