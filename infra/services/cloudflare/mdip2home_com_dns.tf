locals {
  mdip2home_records = {
    # test.mdip2home.com をCloudflare Tunnelに向けるCNAMEレコード
    test = {
      type    = "CNAME"
      name    = "test"
      content = "${cloudflare_zero_trust_tunnel_cloudflared.main["lab_ryuk"].id}.cfargotunnel.com"
      proxied = true
    }
    sub = {
      type    = "CNAME"
      name    = "sub"
      content = "${cloudflare_zero_trust_tunnel_cloudflared.main["sub_mdip2home"].id}.cfargotunnel.com"
      proxied = true
    }
    ledger = {
      type    = "CNAME"
      name    = "ledger"
      content = "${cloudflare_zero_trust_tunnel_cloudflared.main["lawliet_hledger"].id}.cfargotunnel.com"
      proxied = true
    }
  }
}


resource "cloudflare_dns_record" "mdip2home" {
  for_each = local.mdip2home_records

  zone_id  = data.sops_file.cloudflare-secret.data["zone_ids.mdip2home"]
  type     = each.value.type
  name     = each.value.name
  content  = each.value.content
  proxied  = each.value.proxied
  priority = lookup(each.value, "priority", null)
  ttl      = 1
}
