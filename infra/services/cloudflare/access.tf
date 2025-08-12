locals {
  access_apps = {
    "example" = {
      domain = "test.mdip2home.com"
    },
    "subssh" = {
      domain = "sub.mdip2home.com"
    }
    "sma" = {
      domain = "sma.mdip2home.com"
    }
  }
}

resource "cloudflare_zero_trust_access_application" "main" {
  for_each             = local.access_apps
  account_id           = data.sops_file.cloudflare-secret.data["account_id"]
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
    id         = data.sops_file.cloudflare-secret.data["policies.allow_from_japan"]
    precedence = 1
  }]
}
resource "cloudflare_zero_trust_access_policy" "Allow-From-Japan" {
  account_id = data.sops_file.cloudflare-secret.data["account_id"]
  name       = "Allow-From-Japan"
  decision   = "allow"
  include = [
    {
      geo = {
        country_code = "JP"
      }
    },
  ]
}
