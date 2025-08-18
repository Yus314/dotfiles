locals {
  tunnels = {
    "lab_ryuk" = {
      hostname = "test.mdip2home.com"
    },
    "sub_mdip2home" = {
      hostname = "sub.mdip2home.com"
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
      { hostname = each.value.hostname, service = "ssh://localhost:22" },
      { service = "http_status:404" }
    ]
  }
}
