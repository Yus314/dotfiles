
terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    sops = {
      source = "carlpett/sops"
    }
  }
}

data "sops_file" "cloudflare-secret" {
  source_file = "secrets.yaml"
}

provider "cloudflare" {
  api_token = data.sops_file.cloudflare-secret.data["api_token"]
}




