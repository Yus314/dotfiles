terraform {
  required_providers {
    github = {
      source = "integrations/github"
    }
    sops = {
      source = "carlpett/sops"
    }
  }
}

provider "sops" {}

data "sops_file" "secret" {
  source_file = "./secrets.yaml"
}

provider "github" {
  owner = "Yus314"
  token = data.sops_file.secret.data["token"]
}


resource "github_user_ssh_key" "default" {
  title = "mac_book"
  key   = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAHvJKRmO1WHVDdcPTyc7E7t0nLA8QNLt6SqrYC0zCLPP71J7gul03nNwPObQV57H/so1Fgds/tA4NZCAOxDBPmjXwAZG1z6bi/uzUcvviFGZftuh8zB4+jNyZ7yoJZNIpOZNz0Miyo46qg+FSygVmAknxmabh/zvKyDIiv4lpW+8Iz2Vw=="
}

resource "github_user_ssh_key" "sub" {
  title = "lab_main"
  key   = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBABF3IhEIQiwFjYWAuZ+vug+YKI2IGCDMGe637XdOJcffcgdkdBc3wA3SglQNxr25NHS3Zbk5kaq3CV+r4jiksnVpgAQADghKpOZYbE9JZ6JpHAHzPUT4QGawlE3QCGg0D6iOG0Af+oneZSAGc5oIS1LMck5lbuOBwcdgX6mqEsJAyp4vQ=="
}

resource "github_user_ssh_key" "desktop" {
  title = "my_desktop"
  key   = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAGoH/MMMVf2dOmZdh6eppe3zmVmgBCw0CEXHs+VVl6pDWBsZCjBhmwszk6qRXO3hH8vNZlCeqZpTsMVoRxjrYm0xgBks/YXiC9cyPy5sVmvf3Qy4R2DdtgqkJiqei9cZ9ybvjtc92GdYAH5cS88TzLmAgKFFeuK30nchy+qgBHcZQ/bwA=="
}

resource "github_user_gpg_key" "main" {
  armored_public_key = <<EOT
-----BEGIN PGP PUBLIC KEY BLOCK-----

mJMEaFRJexMFK4EEACMEIwQAdMngwf/bk8Stl/7ks6Nww18hyUykWY9RtXQTa+rP
RdgwA1C95mqCdSy8LVRRUob9hlrIsFzgogrAgaNOZ70NCY4AZE6LaclaOmklwex0
Sw3YaaWhy3A7KetkuGoWgSYiXvo/aYizYk8IL4BC8MmMMkdXesMCGkeLUspPafpa
ThoyTVm0KVl1c3VrZSBLYWtpbnVtYSA8c2hpemhhb3lvdWppZUBnbWFpbC5jb20+
iNUEExMKADsWIQSw9rGS5CU6Xb0zp/LSqTU67fkgCgUCaFRJewIbAQULCQgHAgIi
AgYVCgkICwIEFgIDAQIeBwIXgAAKCRDSqTU67fkgCrsCAgipsOBp8zqsMbTUFdjL
diojblxIXQBJjQFZTzvvlpLimNSS6NLgD/KhuTBbTX3lDsbu1kzCea4WMj9pQBHe
g2RPVwII6hbIs+Yfo2OcbANaTWqReClCfZ97kjSnS1K3x1RhNGaocFEaXo/s4UkC
zUbvOynQeB8og8M7JF8ZEbVP3N2I4hy4lwRoVEszEgUrgQQAIwQjBADepESx32K0
Y0pJnkVgKt13S8YxJZTSY2xNoYZBWWvsxOmzxxBcbAYzNddZUb39J+7dr6g7ym05
KqJKpTLG3Daz0gDKm/3OZJvquc4rkZXuzHEqo/M2s2vbiT0i9+ib6X5UPwe7K9Bo
fTcADwY9ws5oO7XMduMwR2uOVZQ0hTWoj9dcvQMBCgmIuwQYEwoAIBYhBLD2sZLk
JTpdvTOn8tKpNTrt+SAKBQJoVEszAhsMAAoJENKpNTrt+SAK9GgCCQEesKHUSPpQ
Jx2RdGl0wfHe+zcqbyu9Bw34k1G+xP0wJC6e6bdl2ojhAx+Rv7h8bSkX805Q18Qn
wp7arpZDkzmWmwIHUH3IFdbChFH9Q/rSUcb1wiJx4CVQEw/R4fqYMbNQPQ0LDcRx
IdjSZCBYasvq6L4MGQRe8bwVy4O685dbanesYEy4kwRoVE0MEwUrgQQAIwQjBAHv
JKRmO1WHVDdcPTyc7E7t0nLA8QNLt6SqrYC0zCLPP71J7gul03nNwPObQV57H/so
1Fgds/tA4NZCAOxDBPmjXwAZG1z6bi/uzUcvviFGZftuh8zB4+jNyZ7yoJZNIpOZ
Nz0Miyo46qg+FSygVmAknxmabh/zvKyDIiv4lpW+8Iz2V4kBdgQYEwoAIBYhBLD2
sZLkJTpdvTOn8tKpNTrt+SAKBQJoVE0MAhsiAMQJENKpNTrt+SAKuSAEGRMKAB0W
IQQ/9RV3mqxbEbrkHACpzRBvIMt+hQUCaFRNDAAKCRCpzRBvIMt+hUgYAgijtlTn
M0l1ipuMtsk4/sznoeV2ccMlLlczCMNgXGu1vbyX3JL27OkNb+HEyG5IA/4CNjPo
MsH3K6O2p978nb0QqwIJAQZsxcPMbyov4NRaplICYxlGsD7e4ez4v+LfWNrrvUhS
zVgX52QisT4zjj9VVUo7WdXM3Bz93tJulPBRnf0ACb/CmX8CCQFdITSc2FtFupXS
0l1Od+6L0yLVQoPktyzhoHfRESTZMtNVjlyOKiQ/YlcwSARKm4Oth0yVnp8F51jK
bvdZH0V2agIJAXSxUHHEaGMOWVBnauamIwZV9qkGIvCRFF51vFocwkredXGxyXHl
F8TkrjHoD1xclctqoCVlsZS6Xut3xrdfZ4qL
=jW8g
-----END PGP PUBLIC KEY BLOCK-----
EOT
}
