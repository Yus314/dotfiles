#!/usr/bin/env bash
# Terraform 汎用OCIバックエンドラッパー（sops.nix統合版）

set -euo pipefail

# ========================================
# 設定値
# ========================================
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly TF_WRAPPER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tf-wrapper"

# カラー定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ログレベル
readonly LOG_LEVEL="${TF_LOG_LEVEL:-INFO}"

# ========================================
# ユーティリティ関数
# ========================================
log_error() { echo -e "${RED}❌ ERROR: $*${NC}" >&2; }
log_warn() { echo -e "${YELLOW}⚠️  WARN: $*${NC}" >&2; }
log_info() { [[ $LOG_LEVEL != "ERROR" ]] && echo -e "${BLUE}ℹ️  INFO: $*${NC}"; }
log_success() { echo -e "${GREEN}✅ SUCCESS: $*${NC}"; }

# ========================================
# 設定ファイル解析
# ========================================
parse_config() {
  local config_file="$1"
  local key="$2"
  local default="${3:-}"

  # sops.nixによって復号化済みの平文YAMLファイルとして処理
  yq eval ".$key // \"$default\"" "$config_file" 2>/dev/null || echo "$default"
}

# ========================================
# バックエンドキー生成
# ========================================
generate_backend_key() {
  local current_dir parent_dir
  current_dir="$(basename "$PWD")"
  parent_dir="$(basename "$(dirname "$PWD")")"

  # ディレクトリ構造に基づくキー生成
  if [[ $parent_dir == "services" ]]; then
    echo "services/${current_dir}/terraform.tfstate"
  else
    echo "${current_dir}/terraform.tfstate"
  fi
}

# ========================================
# OCI設定ファイル検出
# ========================================
detect_config_files() {
  # sops.nix管理ファイルの存在確認（個別ファイル形式）
  local config_dir="$TF_WRAPPER_CONFIG_DIR"

  # 1. 環境変数による設定ディレクトリ上書き
  if [[ -n ${TF_WRAPPER_CONFIG_DIR_OVERRIDE:-} ]]; then
    config_dir="$TF_WRAPPER_CONFIG_DIR_OVERRIDE"
  fi

  # 2. プロジェクトローカル設定（オプション）
  if [[ -f "./tf-wrapper-oci.yaml" ]]; then
    export TF_WRAPPER_LOCAL_CONFIG="./tf-wrapper-oci.yaml"
    log_info "プロジェクトローカル設定を使用: ./tf-wrapper-oci.yaml"
    return 0
  fi

  # 必須ファイルの存在確認
  local required_files=(
    "$config_dir/tenancy.txt"
    "$config_dir/user.txt"
    "$config_dir/fingerprint.txt"
    "$config_dir/backend-bucket.txt"
    "$config_dir/backend-namespace.txt"
    "$config_dir/backend-region.txt"
    "$config_dir/private_key.pem"
  )

  local missing_files=()
  for file in "${required_files[@]}"; do
    if [[ ! -f $file ]]; then
      missing_files+=("$file")
    fi
  done

  if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_error "必須設定ファイルが見つかりません:"
    for file in "${missing_files[@]}"; do
      echo "  - $file"
    done
    log_info "sops.nixによって自動生成されるはずです。Home Manager設定を確認してください。"
    return 1
  fi

  # グローバル変数として設定ディレクトリを保存
  export TF_WRAPPER_CONFIG_DIR_RESOLVED="$config_dir"

  log_success "設定ファイル検出完了"
  log_info "設定ディレクトリ: $config_dir"

  return 0
}

# ========================================
# OCI環境変数設定
# ========================================
setup_oci_environment() {
  log_info "OCI環境設定開始"

  # プロジェクトローカル設定がある場合
  if [[ -n ${TF_WRAPPER_LOCAL_CONFIG:-} ]]; then
    # 従来の設定ファイル解析を使用
    local tenancy_ocid user_ocid fingerprint
    tenancy_ocid=$(parse_config "$TF_WRAPPER_LOCAL_CONFIG" "tenancy_ocid")
    user_ocid=$(parse_config "$TF_WRAPPER_LOCAL_CONFIG" "user_ocid")
    fingerprint=$(parse_config "$TF_WRAPPER_LOCAL_CONFIG" "fingerprint")

    export TF_VAR_tenancy_ocid="$tenancy_ocid"
    export TF_VAR_user_ocid="$user_ocid"
    export TF_VAR_fingerprint="$fingerprint"

    # バックエンド設定
    local bucket namespace region
    bucket=$(parse_config "$TF_WRAPPER_LOCAL_CONFIG" "bucket")
    namespace=$(parse_config "$TF_WRAPPER_LOCAL_CONFIG" "namespace")
    region=$(parse_config "$TF_WRAPPER_LOCAL_CONFIG" "region")

    export TF_VAR_bucket="$bucket"
    export TF_VAR_namespace="$namespace"
    export TF_VAR_region="$region"

    # 秘密鍵はローカル設定から
    local private_key
    private_key=$(parse_config "$TF_WRAPPER_LOCAL_CONFIG" "private_key")
    if [[ -n $private_key && $private_key != "null" ]]; then
      # 一時ファイル作成（ローカル設定の場合のみ）
      TMP_KEY_FILE=$(mktemp -t "tf_wrapper_XXXXXX.pem")
      chmod 600 "$TMP_KEY_FILE"
      echo "$private_key" >"$TMP_KEY_FILE"
      export TF_VAR_private_key_path="$TMP_KEY_FILE"
    fi
  else
    # sops.nix管理の個別ファイルから読み取り
    local config_dir="$TF_WRAPPER_CONFIG_DIR_RESOLVED"

    # 環境変数の宣言
    export TF_VAR_tenancy_ocid TF_VAR_user_ocid TF_VAR_fingerprint
    export TF_VAR_bucket TF_VAR_namespace TF_VAR_region TF_VAR_private_key_path

    # 値の代入
    TF_VAR_tenancy_ocid="$(cat "$config_dir/tenancy.txt")"
    TF_VAR_user_ocid="$(cat "$config_dir/user.txt")"
    TF_VAR_fingerprint="$(cat "$config_dir/fingerprint.txt")"
    TF_VAR_bucket="$(cat "$config_dir/backend-bucket.txt")"
    TF_VAR_namespace="$(cat "$config_dir/backend-namespace.txt")"
    TF_VAR_region="$(cat "$config_dir/backend-region.txt")"
    TF_VAR_private_key_path="$config_dir/private_key.pem"
  fi

  # キーの設定（環境変数優先、なければ自動生成）
  local backend_key
  backend_key="${TF_VAR_key:-$(generate_backend_key)}"
  export TF_VAR_key="$backend_key"

  # 設定値検証
  local missing_vars=()
  [[ -z ${TF_VAR_tenancy_ocid} ]] && missing_vars+=("tenancy_ocid")
  [[ -z ${TF_VAR_user_ocid} ]] && missing_vars+=("user_ocid")
  [[ -z ${TF_VAR_fingerprint} ]] && missing_vars+=("fingerprint")
  [[ -z ${TF_VAR_bucket} ]] && missing_vars+=("bucket")
  [[ -z ${TF_VAR_namespace} ]] && missing_vars+=("namespace")
  [[ -z ${TF_VAR_region} ]] && missing_vars+=("region")
  [[ -z ${TF_VAR_private_key_path} ]] && missing_vars+=("private_key_path")

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log_error "必須設定が不足しています: ${missing_vars[*]}"
    return 1
  fi

  # 設定確認（デバッグモード時のみ）
  if [[ ${TF_DEBUG:-0} == "1" ]]; then
    log_info "設定内容:"
    echo "  TF_VAR_tenancy_ocid: ${TF_VAR_tenancy_ocid:0:20}..."
    echo "  TF_VAR_user_ocid: ${TF_VAR_user_ocid:0:20}..."
    echo "  TF_VAR_fingerprint: ${TF_VAR_fingerprint}"
    echo "  TF_VAR_bucket: ${TF_VAR_bucket}"
    echo "  TF_VAR_namespace: ${TF_VAR_namespace}"
    echo "  TF_VAR_region: ${TF_VAR_region}"
    echo "  TF_VAR_key: ${TF_VAR_key}"
    echo "  TF_VAR_private_key_path: ${TF_VAR_private_key_path}"
  fi

  log_success "OCI環境設定完了"
  log_info "Backend Key: $backend_key"
}

# ========================================
# 前提条件チェック
# ========================================
check_prerequisites() {
  local missing_tools=()

  # 必須ツールチェック（sops.nix利用によりsopsは不要）
  for tool in yq terraform; do
    if ! command -v "$tool" &>/dev/null; then
      missing_tools+=("$tool")
    fi
  done

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    log_error "必須ツールが見つかりません: ${missing_tools[*]}"
    log_info "nix develop環境で実行するか、必要なツールをインストールしてください"
    return 1
  fi

  return 0
}

# ========================================
# Terraform実行
# ========================================
run_terraform() {
  local tf_command="${1:-help}"
  shift || true

  # 特殊コマンド処理（認証なしで実行）
  case "$tf_command" in
  "--help" | "-h" | "help")
    show_help
    exit 0
    ;;
  "--version" | "-v" | "version")
    terraform version
    exit 0
    ;;
  esac

  log_info "Terraform実行中: terraform $tf_command $*"
  terraform "$tf_command" "$@"
}

# ========================================
# ヘルプ表示
# ========================================
show_help() {
  cat <<EOF
Terraform 汎用OCIバックエンドラッパー（sops.nix統合版）

使用方法:
    $SCRIPT_NAME [terraform-command] [options]

例:
    $SCRIPT_NAME init
    $SCRIPT_NAME plan
    $SCRIPT_NAME apply -auto-approve
    $SCRIPT_NAME destroy

設定ファイル:
    ~/.config/tf-wrapper/tenancy.txt         OCI tenancy ID（sops.nixにより自動生成）
    ~/.config/tf-wrapper/user.txt           OCI user ID（sops.nixにより自動生成）
    ~/.config/tf-wrapper/fingerprint.txt    OCI fingerprint（sops.nixにより自動生成）
    ~/.config/tf-wrapper/backend-*.txt      Backend設定（sops.nixにより自動生成）
    ~/.config/tf-wrapper/private_key.pem    OCI秘密鍵（sops.nixにより自動生成）
    ./tf-wrapper-oci.yaml                   プロジェクトローカル設定（オプション）

環境変数:
    TF_WRAPPER_CONFIG_DIR_OVERRIDE  設定ディレクトリの上書き
    TF_VAR_key                      Backend key (デフォルト: 自動生成)
    TF_DEBUG=1                      デバッグ情報表示
    TF_LOG_LEVEL=ERROR              エラーのみ表示
    TF_WRAPPER_CLEANUP_ENV=1        終了時に環境変数をクリーンアップ

機能:
    - sops.nixによる自動設定管理
    - OCI認証情報の安全な配置
    - 環境変数の自動設定
    - 汎用プロジェクト対応
    - セキュリティ強化（一時ファイル不要）

注意:
    このラッパーはHome Managerとsops.nixの統合により動作します。
    設定が見つからない場合、Home Manager設定を確認してください。

EOF
}

# ========================================
# クリーンアップ処理
# ========================================
cleanup() {
  local exit_code=$?

  # 一時秘密鍵ファイルの削除（プロジェクトローカル設定の場合のみ）
  if [[ -n ${TMP_KEY_FILE:-} ]] && [[ -f $TMP_KEY_FILE ]]; then
    log_info "一時秘密鍵ファイルを削除中: $TMP_KEY_FILE"
    if command -v shred &>/dev/null; then
      shred -vfz "$TMP_KEY_FILE" 2>/dev/null || rm -f "$TMP_KEY_FILE"
    else
      rm -f "$TMP_KEY_FILE"
    fi
  fi

  # 環境変数のクリーンアップ（オプション）
  if [[ ${TF_WRAPPER_CLEANUP_ENV:-0} == "1" ]]; then
    unset TF_VAR_tenancy_ocid TF_VAR_user_ocid TF_VAR_fingerprint TF_VAR_private_key_path 2>/dev/null || true
    unset TF_VAR_bucket TF_VAR_namespace TF_VAR_region TF_VAR_key 2>/dev/null || true
  fi

  exit $exit_code
}

# ========================================
# メイン処理
# ========================================
main() {
  # trapでクリーンアップを設定
  trap cleanup EXIT INT TERM

  local tf_command="${1:-help}"

  # 認証不要なコマンドかチェック
  case "$tf_command" in
  "--help" | "-h" | "help" | "--version" | "-v" | "version")
    # 認証設定なしで直接実行
    run_terraform "$@"
    exit 0
    ;;
  esac

  # 前提条件チェック
  check_prerequisites || exit 1

  # 設定ファイル検出
  if ! detect_config_files; then
    exit 1
  fi

  # OCI環境設定
  setup_oci_environment || exit 1

  # Terraform実行
  run_terraform "$@"
}

# スクリプト実行
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
fi
