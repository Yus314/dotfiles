{
  fetchFromGitHub,
  melpaBuild,
  compat,
}:
melpaBuild rec {
  pname = "org-modern-indent";
  version = "0.5";
  src = fetchFromGitHub {
    owner = "jdtsmith";
    repo = "org-modern-indent";
    rev = "b8f3b2e4768951f9846994d653367bae2b491eba";
    sha256 = "sha256-RxvjqWiGY77pO+tO2zgkNU0trcD2tA7A1qLQ6F+CP+s=";
  };
  packageRequires = [
    compat
  ];
}
