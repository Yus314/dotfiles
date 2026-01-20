{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "khalorg";
  version = "0.1.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "BartSte";
    repo = "khalorg";
    rev = "v${version}";
    hash = "sha256-5oZqyHNugvdGKAehSKiKOuIx9KtNTQAwIFEdfK/MDS4=";
  };

  build-system = with python3Packages; [
    setuptools
    setuptools-scm
  ];

  dependencies = with python3Packages; [
    icalendar
    (pkgs.khal)
    orgparse
    vdirsyncer
  ];
  postPatch = ''
    substituteInPlace pyproject.toml --replace "icalendar<6.0" "icalendar"
  '';

  pythonImportsCheck = [ "khalorg" ];

  meta = with lib; {
    description = "An interface between org mode and khal cli calendar";
    homepage = "https://github.com/BartSte/khalorg";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "khalorg";
  };
}
