{
  stdenv,
  fetchurl,
  makeWrapper,
  utillinux,
  jre,
  jdk,
  opencv,
  lsb-release,
  tesseract,
  xdotool,
  wmctrl,
}:

stdenv.mkDerivation rec {
  name = "sikulix-${version}";
  version = "2.0.5";

  #  ide = fetchurl {
  #    url = "https://oss.sonatype.org/content/groups/public/com/sikulix/sikulixsetupIDE/${version}-SNAPSHOT/sikulixsetupIDE-${version}-20170329.090402-140-forsetup.jar";
  #    sha256 = "04hf7awhz7ndxbnif07v3n1sgq03qpk52s298mkdnw86803spbz8";
  # };
  ide = fetchurl {
    url = "https://launchpad.net/sikuli/sikulix/2.0.5/+download/sikulixide-2.0.5-lux.jar";
    sha256 = "sha256-XmlIcQVhscqO0p8JwgZqYXbGENoFOXWx0mXZJ0fxLaA=";
  };

  #  api = fetchurl {
  #    url = "https://oss.sonatype.org/content/groups/public/com/sikulix/sikulixsetupAPI/${version}-SNAPSHOT/sikulixsetupAPI-${version}-20170329.090133-142-forsetup.jar";
  #    sha256 = "0779ryv0qaqpcpl5ana36q98zika9dnx2j29sdabvy2ap01pwb66";
  #  };

  jython = fetchurl {
    url = "http://repo1.maven.org/maven2/org/python/jython-standalone/2.7.1/jython-standalone-2.7.1.jar";
    sha256 = "0jwc4ly75cna78blnisv4q8nfcn5s0g4wk7jf4d16j0rfcd0shf4";
  };

  #  jruby = fetchurl {
  #    url = "http://repo1.maven.org/maven2/org/jruby/jruby-complete/1.7.22/jruby-complete-1.7.22.jar";
  #    sha256 = "1pvmn10lb873i0fsxn4mwxca2r476qrxwhdiz4n5qlfrnxy809id";
  #  };

  #  native = fetchurl {
  #    url = "https://oss.sonatype.org/content/groups/public/com/sikulix/sikulixlibslux/${version}-SNAPSHOT/sikulixlibslux-${version}-20170329.085133-153.jar";
  #    sha256 = "0ssdcp43wsigx9x5gigy266a2ls4wxqh3m90i55jpi59a3axqzmq";
  #  };

  #  setup = fetchurl {
  #    url = "https://launchpad.net/sikuli/sikulix/${version}/+download/sikulixsetup-${version}.jar";
  #    sha256 = "0rwll7rl51ry8nirl91znsvjh6s5agal0wxzqpisr907g1l1vp12";
  #  };

  buildInputs = [
    makeWrapper
    jre
    jdk
    opencv
    lsb-release
    tesseract
    xdotool
    wmctrl
  ];
  propagatedBuildInputs = [ lsb-release ];

  unpackPhase = "true";

  NIX_CFLAGS_COMPILE = "-ltesseract -lopencv_core -lopencv_highgui -lopencv_imgproc -I${jdk}/include";

  installPhase = ''
      cat *.txt
      mkdir -p $out/lib/sikulix
      cp $ide $out/lib/sikulix/sikulixide.jar

      makeWrapper ${jre}/bin/java $out/bin/sikulix \
    --add-flags "-Dsun.java2d.opengl=false -jar $out/lib/sikulix/sikulixide.jar"

  '';
}
