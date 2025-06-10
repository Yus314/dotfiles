{
  fetchFromGitHub,
  melpaBuild,
  org-roam,
  ht,
  async,
  f,
  consult,
  org-drill,
  pcre2el,
  ts,
  memoize,
  dash,
  magit,
}:
melpaBuild rec {
  pname = "org-roam-review";
  version = "20250215";
  src = fetchFromGitHub {
    owner = "chrisbarrett";
    repo = "nursery";
    rev = "d142559096b3e3ee288d439c59fa6a30abe1b11f";
    sha256 = "sha256-oGrflni+XsbENNpyahqqX/Wu+Uenc1/zxLsivPZ5SSM=";
  };
  packageRequires = [
    org-roam
    ht
    async
    f
    consult
    org-drill
    pcre2el
    ts
    memoize
    dash
    magit
  ];

}
