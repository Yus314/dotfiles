locals {
  mdip2home_records = {
    # test.mdip2home.com をCloudflare Tunnelに向けるCNAMEレコード
    test = {
      type    = "CNAME"
      name    = "test"
      content = "ac395291-86ed-4f00-bcd2-77f2a9ae7845.cfargotunnel.com"
      proxied = true
    }
    sub = {
      type    = "CNAME"
      name    = "sub"
      content = "7fd731b9-305c-4bf5-8e75-1d333b53fec9.cfargotunnel.com"
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
