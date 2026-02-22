# VM.Standard.A1.Flex 入手 - Codex実装仕様書

## 概要

OCI Always Free の VM.Standard.A1.Flex（4 OCPU / 24 GB RAM）を自動取得するためのTerraform設定と自動リトライスクリプトを実装する。
ホームリージョンは Japan East (Tokyo) を前提とし、OS は Ubuntu に固定する。VCN は新規作成とする。
AD ローテーションは Terraform 側の変数切り替えで行う（スクリプト側では AD を回さない）。

---

## ディレクトリ構造

```
infra/
├── services/
│   └── oci-compute/           # 新規作成
│       ├── main.tf
│       ├── variables.tf
│       ├── networking.tf
│       ├── instances.tf
│       ├── outputs.tf
│       └── secrets.yaml
├── scripts/
│   └── oci-a1-retry.sh        # 新規作成
└── secrets/
    └── infrastructure.yaml    # 更新（compute セクション追加）
```

---

## ファイル実装詳細

### 1. `infra/services/oci-compute/main.tf`

```hcl
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    sops = {
      source = "carlpett/sops"
    }
  }

  backend "oci" {
    bucket    = "terraform-states"
    key       = "services/oci-compute/terraform.tfstate"
    namespace = "nr8pzcksrfds"
    region    = "ap-tokyo-1"

    # OCI認証情報は環境変数から設定（tf-wrapperが自動設定）
    # TF_VAR_tenancy_ocid
    # TF_VAR_user_ocid
    # TF_VAR_fingerprint
    # TF_VAR_private_key_path
  }
}

data "sops_file" "secrets" {
  source_file = "secrets.yaml"
}

locals {
  secrets               = yamldecode(data.sops_file.secrets.raw)
  selected_ad_number    = var.availability_domain_order[var.availability_domain_attempt - 1]
  selected_ad_name      = data.oci_identity_availability_domains.ads.availability_domains[local.selected_ad_number - 1].name
  selected_compartment  = local.secrets.compartment_ocid
  selected_image_ocid   = coalesce(var.image_ocid, local.secrets.image_ocid)
}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

# 利用可能なAvailability Domainを取得
data "oci_identity_availability_domains" "ads" {
  compartment_id = local.selected_compartment
}
```

### 2. `infra/services/oci-compute/variables.tf`

```hcl
# OCI認証（tf-wrapperから環境変数で設定）
variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "fingerprint" {
  description = "OCI API Key Fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API Private Key"
  type        = string
}

# リージョン設定
variable "region" {
  description = "OCI Region"
  type        = string
  default     = "ap-tokyo-1"
}

# インスタンス設定
variable "instance_display_name" {
  description = "Display name for the instance"
  type        = string
  default     = "a1-flex-free"
}

variable "instance_shape" {
  description = "Instance shape"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs"
  type        = number
  default     = 4
}

variable "instance_memory_gb" {
  description = "Memory in GB"
  type        = number
  default     = 24
}

# OSイメージ（Ubuntu固定）
variable "image_ocid" {
  description = "OS Image OCID (Ubuntu ARM, Always Free eligible)"
  type        = string
  default     = null
}

# SSH（自宅IPのみ許可）
variable "ssh_allowed_cidr" {
  description = "Home IP CIDR for SSH (e.g., 203.0.113.10/32)"
  type        = string
}

# ネットワーク
variable "vcn_cidr_block" {
  description = "VCN CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

# Availability Domain ローテーション（Terraform側で順番に試す）
variable "availability_domain_order" {
  description = "AD order to try (e.g., [1,2,3])"
  type        = list(number)
  default     = [1, 2, 3]
}

variable "availability_domain_attempt" {
  description = "1-based index into availability_domain_order"
  type        = number
  default     = 1
}
```

### 3. `infra/services/oci-compute/networking.tf`

```hcl
# Virtual Cloud Network
resource "oci_core_vcn" "main" {
  compartment_id = local.selected_compartment
  cidr_blocks    = [var.vcn_cidr_block]
  display_name   = "a1-flex-vcn"
  dns_label      = "a1flexvcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "main" {
  compartment_id = local.selected_compartment
  vcn_id         = oci_core_vcn.main.id
  display_name   = "a1-flex-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "main" {
  compartment_id = local.selected_compartment
  vcn_id         = oci_core_vcn.main.id
  display_name   = "a1-flex-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# Security List
resource "oci_core_security_list" "main" {
  compartment_id = local.selected_compartment
  vcn_id         = oci_core_vcn.main.id
  display_name   = "a1-flex-sl"

  # Egress: Allow all outbound
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Ingress: SSH (port 22)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.ssh_allowed_cidr
    stateless   = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress: ICMP (ping)
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress: HTTP (port 80) - optional
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Ingress: HTTPS (port 443) - optional
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    tcp_options {
      min = 443
      max = 443
    }
  }
}

# Subnet
resource "oci_core_subnet" "main" {
  compartment_id             = local.selected_compartment
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.subnet_cidr_block
  display_name               = "a1-flex-subnet"
  dns_label                  = "a1flexsubnet"
  route_table_id             = oci_core_route_table.main.id
  security_list_ids          = [oci_core_security_list.main.id]
  prohibit_public_ip_on_vnic = false

  # ADはTerraform側で順番に切り替える
  availability_domain = local.selected_ad_name
}
```

### 4. `infra/services/oci-compute/instances.tf`

```hcl
# VM.Standard.A1.Flex Instance
resource "oci_core_instance" "a1_flex" {
  compartment_id      = local.selected_compartment
  availability_domain = local.selected_ad_name
  display_name        = var.instance_display_name
  shape               = var.instance_shape

  # Flexible Shape設定
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  # ブートボリューム設定
  source_details {
    source_type             = "image"
    source_id               = local.selected_image_ocid
    boot_volume_size_in_gbs = 50 # デフォルト。合計200GB枠にカウント
  }

  # ネットワーク設定
  create_vnic_details {
    subnet_id                 = oci_core_subnet.main.id
    display_name              = "${var.instance_display_name}-vnic"
    assign_public_ip          = true
    assign_private_dns_record = true
    hostname_label            = "a1flex"
  }

  # メタデータ（SSH公開鍵）
  metadata = {
    ssh_authorized_keys = local.secrets.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  # Always Free対象インスタンスのため、preemptibleは設定しない
  # preemptible_instance_config は設定しないこと

  lifecycle {
    # Out of Capacity エラー時にリトライするため
    # create_before_destroy は使用しない
    ignore_changes = [
      defined_tags,
      freeform_tags,
    ]
  }
}

# Instance VNIC (Public/Private IP取得用)
data "oci_core_vnic_attachments" "a1_flex" {
  compartment_id = local.selected_compartment
  instance_id    = oci_core_instance.a1_flex.id
}

data "oci_core_vnic" "a1_flex" {
  vnic_id = data.oci_core_vnic_attachments.a1_flex.vnic_attachments[0].vnic_id
}

# Reserved Public IP（オプション: 固定IP）
# 料金条件は公式ドキュメントで要確認
# resource "oci_core_public_ip" "reserved" {
#   compartment_id = local.selected_compartment
#   display_name   = "${var.instance_display_name}-ip"
#   lifetime       = "RESERVED"
# }
```

### 5. `infra/services/oci-compute/cloud-init.yaml`

```yaml
#cloud-config

# パッケージ更新
package_update: true
package_upgrade: true

# 基本パッケージインストール
packages:
  - vim
  - curl
  - wget
  - git
  - htop
  - tmux
  - fail2ban

# タイムゾーン設定
timezone: Asia/Tokyo

# SSH設定強化
ssh_pwauth: false

# 最終メッセージ
final_message: "Cloud-init completed after $UPTIME seconds"

# 再起動（カーネル更新がある場合）
power_state:
  mode: reboot
  condition: true
  timeout: 30
```

### 6. `infra/services/oci-compute/outputs.tf`

```hcl
output "instance_id" {
  description = "Instance OCID"
  value       = oci_core_instance.a1_flex.id
}

output "instance_public_ip" {
  description = "Public IP address"
  value       = data.oci_core_vnic.a1_flex.public_ip_address
}

output "instance_private_ip" {
  description = "Private IP address"
  value       = data.oci_core_vnic.a1_flex.private_ip_address
}

output "instance_state" {
  description = "Instance state"
  value       = oci_core_instance.a1_flex.state
}

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.main.id
}

output "subnet_id" {
  description = "Subnet OCID"
  value       = oci_core_subnet.main.id
}

output "ssh_command" {
  description = "SSH connection command"
  value       = "ssh ubuntu@${data.oci_core_vnic.a1_flex.public_ip_address}"
}

output "availability_domain" {
  description = "Availability Domain"
  value       = oci_core_instance.a1_flex.availability_domain
}
```

### 7. `infra/services/oci-compute/secrets.yaml`

SOPSで暗号化する前のプレーンテキスト形式（暗号化が必要）:

```yaml
# sops -e -i secrets.yaml で暗号化すること

# Compartment OCID（ユーザーが取得して設定）
compartment_ocid: "ocid1.compartment.oc1..xxxxx"

# Ubuntu 22.04 ARM Image OCID（リージョンごとに異なる）
# ap-tokyo-1 の場合: https://docs.oracle.com/en-us/iaas/images/
image_ocid: "ocid1.image.oc1.ap-tokyo-1.xxxxx"

# SSH公開鍵（OCI専用鍵を使用）
ssh_public_key: "ssh-ed25519 AAAA... user@host"

# OSは Ubuntu の Always Free eligible イメージのみ使用
```

### 8. `infra/scripts/oci-a1-retry.sh`

```bash
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
```

---

## SOPS secrets/infrastructure.yaml への追加（必要な場合のみ）

tf-wrapper 側で `infra/secrets/infrastructure.yaml` を参照する運用がある場合のみ、以下を追加:

```yaml
# 既存のoci:セクションの下に追加
oci:
  root:
    # ... 既存の設定 ...
  compute:
    compartment_ocid: "ocid1.compartment.oc1..xxxxx"  # ユーザーが設定
    image_ocid: "ocid1.image.oc1.ap-tokyo-1.xxxxx"
    ssh_public_key: "ssh-ed25519 AAAA... user@host"
```

SOPSで暗号化:
```bash
cd infra/secrets
sops infrastructure.yaml  # エディタで編集
# または
sops -e -i infrastructure.yaml  # 再暗号化
```

---

## 実行手順

### 1. 事前準備（ユーザー操作）

OCIコンソールから以下を取得:

| 項目 | 取得場所 | 例 |
|------|----------|-----|
| Compartment OCID | Identity → Compartments | `ocid1.compartment.oc1..xxxxx` |
| Image OCID | Compute → Custom Images または [公式リスト](https://docs.oracle.com/en-us/iaas/images/) | Ubuntu 22.04 ARM |
| SSH公開鍵 | ローカル（OCI専用鍵: 例 `~/.ssh/oci_a1.pub`） | `ssh-ed25519 AAAA...` |
| 自宅IP CIDR | `https://ifconfig.me` などで確認 | `203.0.113.10/32` |

### 2. シークレット設定

```bash
cd infra/services/oci-compute

# OCI専用鍵を作成（未作成の場合）
ssh-keygen -t ed25519 -C "oci-a1" -f ~/.ssh/oci_a1

# secrets.yamlを作成（上記テンプレートを参照）
vim secrets.yaml

# SOPSで暗号化
sops -e -i secrets.yaml
```

### 3. Terraform初期化と確認

```bash
cd infra/services/oci-compute

# 初期化
tf-wrapper init

# プラン確認（初回はAD1）
tf-wrapper plan -var='availability_domain_attempt=1' -var='ssh_allowed_cidr=203.0.113.10/32'
```

### 4. AD切り替え（Terraform側）

Out of Capacity が続く場合、ADを順番に切り替えて再試行:

```bash
# AD 1 → AD 2 → AD 3 の順で試す
tf-wrapper apply -auto-approve -var='availability_domain_attempt=1' -var='ssh_allowed_cidr=203.0.113.10/32'
tf-wrapper apply -auto-approve -var='availability_domain_attempt=2' -var='ssh_allowed_cidr=203.0.113.10/32'
tf-wrapper apply -auto-approve -var='availability_domain_attempt=3' -var='ssh_allowed_cidr=203.0.113.10/32'
```

### 5. 自動リトライ実行（同一AD内の再試行）

```bash
# 実行権限付与
chmod +x infra/scripts/oci-a1-retry.sh

# バックグラウンド実行（推奨: screen/tmux使用）
screen -S oci-retry
# 例: AD1を固定してリトライ
TF_VAR_availability_domain_attempt=1 TF_VAR_ssh_allowed_cidr=203.0.113.10/32 ./infra/scripts/oci-a1-retry.sh

# Ctrl+A, D でデタッチ
# screen -r oci-retry で再接続
```

### 6. 成功確認

```bash
# 出力確認
cd infra/services/oci-compute
tf-wrapper output

# SSH接続テスト
ssh ubuntu@<public_ip>
```

---

## 注意事項

1. **リトライ時間**: キャパシティ空きまで数時間〜数週間かかる可能性
2. **アイドルポリシー**: 7日間でCPU使用率95%ile < 20%のインスタンスはOracle回収対象
3. **PAYG推奨**: より確実に取得したい場合はPay As You Goへアップグレード
4. **ネットワーク**: VCN/Subnet作成でAlways Free枠は消費しない
5. **自宅IPが変動する場合**: 変動のたびに `ssh_allowed_cidr` を更新し、`tf-wrapper apply` で Security List を反映する

---

## 参考リソース

- [OCI Compute Shapes](https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm)
- [Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [oracle-freetier-instance-creation](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation)
- [oci-arm-host-capacity](https://github.com/hitrov/oci-arm-host-capacity)
