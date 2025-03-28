{
  fetchFromGitHub,
  melpaBuild,
  dash,
  s,
}:
melpaBuild rec {
  pname = "ol-emacs-slack";
  version = "20240718";
  src = fetchFromGitHub {
    owner = "ag91";
    repo = "ol-emacs-slack";
    rev = "299bd86280179999b049abc7252eb1bffa8a5ddd";
    sha256 = "sha256-uEVJYAqVolyL8Li7zagl/4XcgkNJH+JIupLsh7tJhEE=";
  };
  propagatedUserEnvPkgs = [
    dash
    s
  ];
  buildInputs = propagatedUserEnvPkgs;
}
