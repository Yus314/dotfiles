locals {
  access_apps = {
    "example" = {
      domain = "test.mdip2home.com"
    },
    "subssh" = {
      domain = "sub.mdip2home.com"
    }
  }
}

resource "cloudflare_zero_trust_access_application" "main" {
  for_each             = local.access_apps
  account_id           = var.cloudflare_account_id
  name                 = each.key
  domain               = each.value.domain
  type                 = "self_hosted"
  session_duration     = "730h"
  app_launcher_visible = true
  destinations = [
    {
      type = "public"
      uri  = each.value.domain
    },
  ]
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  options_preflight_bypass   = false
  policies = [{
    name     = "Allow-From-Japan" # ポリシーの共通名
    decision = "allow"
    include = [
      {
        geo = { country_code = "JP" } # 日本からのアクセスを許可
      }
    ]
  }]
}
resource "cloudflare_zero_trust_access_policy" "common" {
  for_each   = cloudflare_zero_trust_access_application.main
  account_id = var.cloudflare_account_id
  name       = "common"
  decision   = "allow"
  include = [
    {
      geo = {
        country_code = "JP"
      }
    },
  ]
}
