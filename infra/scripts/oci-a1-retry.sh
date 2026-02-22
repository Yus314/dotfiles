#!/usr/bin/env bash
# ==============================================================================
# OCI VM.Standard.A1.Flex 自動取得スクリプト
# Out of Capacity エラー時に自動リトライ
# ==============================================================================

set -uo pipefail

# ==============================================================================
# 設定
# ==============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TERRAFORM_DIR="${SCRIPT_DIR}/../services/oci-compute"
readonly LOG_FILE="${SCRIPT_DIR}/oci-a1-retry.log"
readonly STATE_FILE="${SCRIPT_DIR}/.oci-a1-retry.state"

# リトライ設定
RETRY_INTERVAL="${RETRY_INTERVAL:-60}"          # リトライ間隔（秒）
MAX_RETRIES="${MAX_RETRIES:-10080}"             # 最大リトライ回数（7日間: 60秒 × 10080）
NOTIFY_ON_SUCCESS="${NOTIFY_ON_SUCCESS:-true}"  # 成功時に通知

# 通知設定（オプション）
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# カラー定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ==============================================================================
# ユーティリティ関数
# ==============================================================================
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# ==============================================================================
# 通知関数
# ==============================================================================
notify_discord() {
  local message="$1"
  if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    curl -s -H "Content-Type: application/json" \
      -d "{\"content\": \"$message\"}" \
      "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi
}

notify_telegram() {
  local message="$1"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    curl -s -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${message}" >/dev/null 2>&1 || true
  fi
}

notify_success() {
  local public_ip="$1"
  local message="🎉 OCI A1.Flex instance created successfully!\n\nPublic IP: ${public_ip}\nSSH: ssh ubuntu@${public_ip}"

  log_success "Instance created! Public IP: $public_ip"

  if [[ "$NOTIFY_ON_SUCCESS" == "true" ]]; then
    notify_discord "$message"
    notify_telegram "$message"
  fi
}

# ==============================================================================
# Terraform操作
# ==============================================================================
terraform_init() {
  log_info "Initializing Terraform..."
  cd "$TERRAFORM_DIR"
  tf-wrapper init -input=false 2>&1 | tee -a "$LOG_FILE"
  return ${PIPESTATUS[0]}
}

terraform_apply() {
  log_info "Attempting to create instance..."
  cd "$TERRAFORM_DIR"

  # apply実行、出力をキャプチャ
  local output
  output=$(tf-wrapper apply -auto-approve -input=false 2>&1)
  local exit_code=$?

  echo "$output" | tee -a "$LOG_FILE"

  # Out of Capacity エラーチェック
  if echo "$output" | grep -q "Out of capacity\|Out of host capacity\|InternalError\|ServiceError"; then
    log_warn "Out of Capacity detected. Will retry..."
    return 1
  fi

  return $exit_code
}

get_public_ip() {
  cd "$TERRAFORM_DIR"
  tf-wrapper output -raw instance_public_ip 2>/dev/null || echo ""
}

# ==============================================================================
# 状態管理
# ==============================================================================
save_state() {
  local retry_count="$1"
  echo "retry_count=$retry_count" > "$STATE_FILE"
  echo "last_attempt=$(date -Iseconds)" >> "$STATE_FILE"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    echo "${retry_count:-0}"
  else
    echo "0"
  fi
}

# ==============================================================================
# シグナルハンドラ
# ==============================================================================
cleanup() {
  local exit_code=$?
  log_info "Received signal, cleaning up..."
  log_info "Script stopped after $(load_state) retries"
  exit $exit_code
}

trap cleanup INT TERM

# ==============================================================================
# メイン処理
# ==============================================================================
main() {
  log_info "=========================================="
  log_info "OCI A1.Flex Auto-Retry Script Started"
  log_info "=========================================="
  log_info "Retry Interval: ${RETRY_INTERVAL}s"
  log_info "Max Retries: ${MAX_RETRIES}"
  log_info "Log File: ${LOG_FILE}"
  log_info "=========================================="

  # Terraform初期化
  if ! terraform_init; then
    log_error "Terraform init failed!"
    exit 1
  fi

  # リトライカウンタ（状態ファイルから復元）
  local retry_count
  retry_count=$(load_state)

  if [[ $retry_count -gt 0 ]]; then
    log_info "Resuming from retry #${retry_count}"
  fi

  # リトライループ
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    ((retry_count++))
    log_info "Attempt #${retry_count}/${MAX_RETRIES}"

    if terraform_apply; then
      # 成功
      local public_ip
      public_ip=$(get_public_ip)

      if [[ -n "$public_ip" ]]; then
        notify_success "$public_ip"
        rm -f "$STATE_FILE"
        log_success "=========================================="
        log_success "Instance creation completed!"
        log_success "SSH: ssh ubuntu@${public_ip}"
        log_success "=========================================="
        exit 0
      else
        log_warn "Apply succeeded but no public IP found. Retrying..."
      fi
    fi

    # 状態保存
    save_state "$retry_count"

    # 次のリトライまで待機
    log_info "Waiting ${RETRY_INTERVAL}s before next attempt..."
    sleep "$RETRY_INTERVAL"
  done

  log_error "Max retries (${MAX_RETRIES}) reached. Giving up."
  exit 1
}

# ==============================================================================
# ヘルプ
# ==============================================================================
show_help() {
  cat <<EOF
OCI VM.Standard.A1.Flex 自動取得スクリプト

使用方法:
    $0 [options]

オプション:
    -h, --help      このヘルプを表示
    -i, --interval  リトライ間隔（秒）[default: 60]
    -m, --max       最大リトライ回数 [default: 10080]

環境変数:
    RETRY_INTERVAL          リトライ間隔（秒）
    MAX_RETRIES             最大リトライ回数
    NOTIFY_ON_SUCCESS       成功時に通知 (true/false)
    DISCORD_WEBHOOK_URL     Discord Webhook URL
    TELEGRAM_BOT_TOKEN      Telegram Bot Token
    TELEGRAM_CHAT_ID        Telegram Chat ID

例:
    # バックグラウンドで実行
    nohup $0 &

    # screen/tmuxで実行（推奨）
    screen -S oci-retry $0

    # カスタム設定
    RETRY_INTERVAL=120 MAX_RETRIES=5000 $0

EOF
}

# ==============================================================================
# エントリポイント
# ==============================================================================
case "${1:-}" in
  -h|--help)
    show_help
    exit 0
    ;;
  -i|--interval)
    RETRY_INTERVAL="${2:-60}"
    shift 2
    ;;
  -m|--max)
    MAX_RETRIES="${2:-10080}"
    shift 2
    ;;
esac

main "$@"
