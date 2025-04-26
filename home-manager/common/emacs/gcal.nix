{
  melpaBuild,
  fetchFromGitHub,
}:
melpaBuild {
  pname = "gcal";
  version = "20240619";
  src = fetchFromGitHub {
    owner = "misohena";
    repo = "gcal";
    rev = "7b4fc16906850c7be7100d6e239c183ed9a054e4";
    sha256 = "sha256-jU4dwlJaGjufbmOzTe7V/5Av2WuOZGMc49VmeX7yh8Y=";
  };
}
