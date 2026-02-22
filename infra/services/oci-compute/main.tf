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
  secrets              = yamldecode(data.sops_file.secrets.raw)
  selected_ad_number   = var.availability_domain_order[var.availability_domain_attempt - 1]
  selected_ad_name     = data.oci_identity_availability_domains.ads.availability_domains[local.selected_ad_number - 1].name
  selected_compartment = local.secrets.compartment_ocid
  selected_image_ocid  = coalesce(var.image_ocid, local.secrets.image_ocid)
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
