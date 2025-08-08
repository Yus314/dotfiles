#!/bin/bash
# OCI環境変数設定スクリプト（SOPS統合版）
#
# SOPS暗号化されたinfrastructure.yamlから OCI認証情報を読み込み、
# Terraform環境変数として設定します。

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# カラー出力
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }

# OCIネイティブバックエンド用環境変数設定
setup_oci_env() {
  local secrets_file="${1:-$INFRA_DIR/secrets/infrastructure.yaml}"

  info "OCIネイティブバックエンド環境変数設定中..."

  # SOPS統合実装（infrastructure.yamlが暗号化済み）
  if [[ -f $secrets_file ]]; then
    info "SOPSから暗号化されたOCI設定を読み込み中..."

    # SOPS復号化してjqでJSONパース
    eval $(cd "$INFRA_DIR" && nix develop --command bash -c "cd secrets && sops -d infrastructure.yaml" |
      nix run nixpkgs#yq -- -r '.' |
      nix run nixpkgs#jq -- -r '.terraform.backend.oci |
                      "export TF_VAR_tenancy_ocid=\"" + .tenancy_ocid + "\";" +
                      "export TF_VAR_user_ocid=\"" + .user_ocid + "\";" +
                      "export TF_VAR_fingerprint=\"" + .fingerprint + "\";" +
                      "export TF_VAR_private_key_path=\"" + .private_key_path + "\""')

    success "SOPS統合によるOCI認証設定完了"
  else
    warning "infrastructure.yaml not found at: $secrets_file"
    return 1
  fi

  success "OCI環境変数設定完了"
  info "設定内容:"
  echo "  TF_VAR_tenancy_ocid: ${TF_VAR_tenancy_ocid:0:20}..."
  echo "  TF_VAR_user_ocid: ${TF_VAR_user_ocid:0:20}..."
  echo "  TF_VAR_fingerprint: ${TF_VAR_fingerprint}"
  echo "  TF_VAR_private_key_path: ${TF_VAR_private_key_path}"
}

# Terraformラッパー関数
terraform_with_oci() {
  setup_oci_env

  info "OCIネイティブバックエンドでTerraform実行: terraform $*"
  nix develop --command terraform "$@"
}

# 使用方法表示
show_usage() {
  echo "OCIネイティブバックエンド用環境変数設定（SOPS統合版）"
  echo ""
  echo "前提条件:"
  echo "  - Nix環境（sops、yq、jq が利用可能）"
  echo "  - secrets/infrastructure.yaml が暗号化済み"
  echo ""
  echo "使用方法:"
  echo "  source $0                    # 環境変数設定のみ"
  echo "  $0 terraform_with_oci init   # OCI環境でterraform init"
  echo "  $0 terraform_with_oci plan   # OCI環境でterraform plan"
  echo "  $0 terraform_with_oci apply  # OCI環境でterraform apply"
}

# メイン処理
main() {
  local command="${1:-setup}"

  case "$command" in
  "terraform_with_oci")
    shift
    terraform_with_oci "$@"
    ;;
  "setup" | "")
    setup_oci_env
    ;;
  "help" | "-h" | "--help")
    show_usage
    ;;
  *)
    warning "不明なコマンド: $command"
    show_usage
    ;;
  esac
}

# スクリプトが直接実行された場合
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
fi
