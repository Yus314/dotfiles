
terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    sops = {
      source = "carlpett/sops"
    }
  }

  backend "oci" {
    bucket    = "terraform-states"
    key       = "cloudflare/terraform.tfstate"
    namespace = "nr8pzcksrfds"
    region    = "ap-tokyo-1"

    # OCI認証情報は環境変数から設定
    # TF_VAR_tenancy_ocid
    # TF_VAR_user_ocid
    # TF_VAR_fingerprint
    # TF_VAR_private_key_path
  }
}

data "sops_file" "cloudflare-secret" {
  source_file = "secrets.yaml"
}

provider "cloudflare" {
  api_token = data.sops_file.cloudflare-secret.data["api_token"]
}
