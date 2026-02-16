locals {
  tunnels = {
    "lab_ryuk" = {
      hostname = "test.mdip2home.com"
      service  = "ssh://localhost:22"
    },
    "sub_mdip2home" = {
      hostname = "sub.mdip2home.com"
      service  = "ssh://localhost:22"
    },
    "lawliet_hledger" = {
      hostname = "ledger.mdip2home.com"
      service  = "http://localhost:5000"
    }
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  for_each = local.tunnels

  config_src = "cloudflare"
  account_id = data.sops_file.cloudflare-secret.data["account_id"]
  name       = each.key
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  for_each = local.tunnels

  account_id = data.sops_file.cloudflare-secret.data["account_id"]
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main[each.key].id

  config = {
    ingress = [
      { hostname = each.value.hostname, service = each.value.service },
      { service = "http_status:404" }
    ]
  }
}
