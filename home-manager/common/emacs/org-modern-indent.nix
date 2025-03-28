{
  fetchFromGitHub,
  trivialBuild,
}:
trivialBuild {
  pname = "org-modern-indent";
  version = "v0.5";
  src = fetchFromGitHub {
    owner = "jdtsmith";
    repo = "org-modern-indent";
    rev = "fcd4368476a9c4eadfac4d6f51159d90a15de15a";
    sha256 = "sha256-obx83T90LoVor5O5bniXCtWhNV7GmF3fYpNhCNgSm1M=";
  };
}
