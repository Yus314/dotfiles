resource "cloudflare_dns_record" "terraform_managed_resource_eeb8f6ba0d5240b608426ac15e5929ef" {
  content  = "150.95.255.38"
  name     = "lab2home.net"
  proxied  = true
  ttl      = 1
  type     = "A"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_5d5fd57db61f1e383db4977a37134c84" {
  content  = "150.95.255.38"
  name     = "www.lab2home.net"
  proxied  = true
  ttl      = 1
  type     = "A"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_d56f7a9dba6ccd7fd0a8e6e9758a6f59" {
  content  = "be67bd53-41f2-470e-8e48-e61db94e6e19.cfargotunnel.com"
  name     = "ssh.lab2home.net"
  proxied  = true
  ttl      = 1
  type     = "CNAME"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_2d5a42019911526fd2185cef40d578f8" {
  content  = "65be581a-f524-4fd7-b477-9f5108c58fe5.cfargotunnel.com"
  name     = "test.lab2home.net"
  proxied  = true
  ttl      = 1
  type     = "CNAME"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_0bc7195d0a5e8d5fdaac2aebe0b773aa" {
  content  = "."
  name     = "lab2home.net"
  priority = 0
  proxied  = false
  ttl      = 1
  type     = "MX"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_a95d8ca6b4a33829650a910e108edd4a" {
  content  = "."
  name     = "www.lab2home.net"
  priority = 0
  proxied  = false
  ttl      = 1
  type     = "MX"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_4f18e2a0eed4f9178539e3691c20e628" {
  content  = "dns1.onamae.com"
  name     = "aws.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_98860d410d7ba0907d6a9e9b17193100" {
  content  = "dns2.onamae.com"
  name     = "aws.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_4659b34b812822ba62283e1b3ad5a444" {
  content  = "dns2.onamae.com"
  name     = "dev.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_cff77a1e3109ff09c2420ef8d0610aff" {
  content  = "dns1.onamae.com"
  name     = "dev.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_cb18a1bcb254b6b19638c7afeca3d5ea" {
  content  = "dns2.onamae.com"
  name     = "_dmarc.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_be2207a31f7b46867c23d29c45e4fe94" {
  content  = "dns1.onamae.com"
  name     = "_dmarc.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_615b09527d328adf34fe1c5b9b1e6eb0" {
  content  = "dns1.onamae.com"
  name     = "_domainkey.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_fb5d503666b0bfe21dcc2f6b6010c030" {
  content  = "dns2.onamae.com"
  name     = "_domainkey.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_59e60cc59d08a96011b6901f7bc70bdc" {
  content  = "dns1.onamae.com"
  name     = "e.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_f9256144dd3527f8e7e0fe98361edc39" {
  content  = "dns2.onamae.com"
  name     = "e.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_ec1740974518a52342fa7653f1f407ea" {
  content  = "dns1.onamae.com"
  name     = "email.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_4995cd224e0abc184efc1dedd18490f4" {
  content  = "dns2.onamae.com"
  name     = "email.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_cd696ee0d303685ce9670b636a0bec99" {
  content  = "dns1.onamae.com"
  name     = "info.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_8ccaaaa117c430fc2db34d34479fc190" {
  content  = "dns2.onamae.com"
  name     = "info.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_6b1a9d409153d1947a9379a1591b3b7a" {
  content  = "dns2.onamae.com"
  name     = "k8s.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_98e600ddb2bffd5202e553f2c41e1e8e" {
  content  = "dns1.onamae.com"
  name     = "k8s.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_27f7142bf88168608aa9ca08ab2ff69e" {
  content  = "dns2.onamae.com"
  name     = "mail.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_e60b18174ed1cf0c15223096cb730ccb" {
  content  = "dns1.onamae.com"
  name     = "mail.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_4c458435db651a2ed14c5d67a3266192" {
  content  = "dns2.onamae.com"
  name     = "news.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_5074d7f4289869be9ad88d3c5ed44115" {
  content  = "dns1.onamae.com"
  name     = "news.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_a3e1fd39808fc3ed55defcc2a7a93d93" {
  content  = "dns1.onamae.com"
  name     = "newsletter.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_1f980cd226e0af8507fc50e1a9721ee5" {
  content  = "dns2.onamae.com"
  name     = "newsletter.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_d5cd48562fee55a6817281d518be13cc" {
  content  = "dns1.onamae.com"
  name     = "ns1.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_1a9d7fe4dad1ed07bbbc5832727bb643" {
  content  = "dns2.onamae.com"
  name     = "ns1.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_7d4373110ea22af7a37ce75ac60126d1" {
  content  = "dns2.onamae.com"
  name     = "ns2.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_228b2239c370762f2390cc583dfb20de" {
  content  = "dns1.onamae.com"
  name     = "ns2.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_cb37ef5dbc99e1d4d939058fd471914b" {
  content  = "dns2.onamae.com"
  name     = "spf.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_0548b86f6617d30f54a8a3c7a35c8967" {
  content  = "dns1.onamae.com"
  name     = "spf.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_3cb9a12d15cb39f75c47f3d47617ab68" {
  content  = "dns2.onamae.com"
  name     = "test.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_9e6cab8074faf112c680d4bea78556fb" {
  content  = "dns1.onamae.com"
  name     = "test.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_160acdd4702b77a7bcc2e3f062655fc4" {
  content  = "dns2.onamae.com"
  name     = "track.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_c2a6e55ab42e0071900f42409f8be2ac" {
  content  = "dns1.onamae.com"
  name     = "track.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_c2bc4a316ed9ba7e7231bbe233b48864" {
  content  = "dns1.onamae.com"
  name     = "www.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_a1f3fb9d428e086886afccca35dbd02a" {
  content  = "dns2.onamae.com"
  name     = "www.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "NS"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_4c5bb1fa5e87598175e99763a7de1623" {
  content  = "\"v=spf1 -all\""
  name     = "lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "TXT"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_1b275f3c3eeefd6aa22d85fcfe17ab75" {
  content  = "\"v=spf1 -all\""
  name     = "www.lab2home.net"
  proxied  = false
  ttl      = 1
  type     = "TXT"
  zone_id  = "3cd2cb8c57aee21c5baa152222e8657f"
  settings = {}
}


locals {
  mdip2home_records = {
    root = {
      type    = "CNAME"
      name    = "mdip2home.com"
      content = "d2bb7add-9929-4016-a839-0e03a71bdb14.cfargotunnel.com"
      proxied = true
    }
    ollama = {
      type    = "CNAME"
      name    = "ollama" # .mdip2home.com は省略してOK
      content = "cf8072ab-5f24-49fb-ba44-0a67e6f7d676.cfargotunnel.com"
      proxied = true
    }
    # sma.mdip2home.com をCloudflare Tunnelに向けるCNAMEレコード
    sma = {
      type    = "CNAME"
      name    = "sma"
      content = "9010acdf-2105-43ec-984d-8684dd0124bb.cfargotunnel.com"
      proxied = true
    }
    # sub.mdip2home.com をCloudflare Tunnelに向けるCNAMEレコード
    sub = {
      type    = "CNAME"
      name    = "sub"
      content = "533cec7a-befd-4e76-b914-3acfbd34d96e.cfargotunnel.com"
      proxied = true
    }
    # test.mdip2home.com をCloudflare Tunnelに向けるCNAMEレコード
    test = {
      type    = "CNAME"
      name    = "test"
      content = "d2bb7add-9929-4016-a839-0e03a71bdb14.cfargotunnel.com"
      proxied = true
    }
    # www.mdip2home.com をCloudflare Tunnelに向けるCNAMEレコード
    www = {
      type    = "CNAME"
      name    = "www"
      content = "d2bb7add-9929-4016-a839-0e03a71bdb14.cfargotunnel.com"
      proxied = true
    }
    # mail.mdip2home.com のMXレコード
    mx_google = {
      type     = "MX"
      name     = "mail"
      content  = "smtp.google.com"
      priority = 500
      proxied  = false
    }
    # ルートドメインのSPFレコード
    spf = {
      type    = "TXT"
      name    = "mdip2home.com"
      content = "\"v=spf1 include:_spf.google.com ~all\""
      proxied = false
    }
  }
}


resource "cloudflare_dns_record" "mdip2home" {
  for_each = local.mdip2home_records

  zone_id  = "e0efbea3c4dd17f3b289f18516dc5593"
  type     = each.value.type
  name     = each.value.name
  content  = each.value.content
  proxied  = each.value.proxied
  priority = lookup(each.value, "priority", null)
  ttl      = 1
}
