{
  fetchgit,
  melpaBuild,
}:
melpaBuild {
  pname = "typst-ts-mode";
  version = "20240328";
  src = fetchgit {
    url = "https://codeberg.org/meow_king/typst-ts-mode.git";
    rev = "e0542e3e42c55983282115a97c13c023a464ff00";
    sha256 = "sha256-P/6Z4HYwN6A7bcXEiNruv2/NHaoI7DJwYXdJ2z3VEG0="; 
  };
}
