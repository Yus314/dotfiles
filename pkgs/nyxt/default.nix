# Nyxt 4.0.0 with Electron backend
# The build process:
# 1. Fetch source with all Lisp submodules
# 2. Install npm dependencies for cl-electron (offline)
# 3. Rebuild synchronous-socket native module against electron headers
# 4. Build Nyxt with SBCL using the electron renderer
# 5. Install and wrap with runtime dependencies
{
  lib,
  stdenv,
  fetchFromGitHub,
  sbcl,
  pkg-config,
  openssl,
  sqlite,
  libfixposix,
  electron,
  nodejs,
  fetchNpmDeps,
  makeWrapper,
  python3,
  # For clipboard support
  xclip,
  wl-clipboard,
  xdg-utils,
  # For spell checking
  enchant,
}:

let
  version = "4.0.0";

  src = fetchFromGitHub {
    owner = "atlas-engineer";
    repo = "nyxt";
    rev = version;
    hash = "sha256-QG2wCMW/Vs2qBxsoqHSkxv7NQDgKL1c5+CA4TG7MTI0=";
    fetchSubmodules = true;
  };

  # NPM dependencies for cl-electron
  clElectronNpmDeps = fetchNpmDeps {
    name = "cl-electron-npm-deps";
    src = "${src}/_build/cl-electron";
    hash = "sha256-dHuhSAXgWP1wa71kq7P2wVVEEPYm5lsn1h+PRWCGDnQ=";
  };

  # Electron headers for building native modules with correct ABI
  electronHeaders = electron.headers;

in
stdenv.mkDerivation {
  pname = "nyxt";
  inherit version src;

  nativeBuildInputs = [
    sbcl
    pkg-config
    makeWrapper
    nodejs
    (python3.withPackages (ps: [ ps.setuptools ])) # Required for node-gyp
  ];

  buildInputs = [
    openssl
    sqlite
    libfixposix
    enchant
    electron # Needed at runtime
  ];

  # Environment variables for the Nyxt build
  NYXT_SUBMODULES = "true";
  NYXT_RENDERER = "electron";
  NASDF_USE_LOGICAL_PATHS = "true";
  NODE_SETUP = "false";

  # SBCL needs this for CFFI to find libraries
  LD_LIBRARY_PATH = lib.makeLibraryPath [
    openssl
    sqlite
    libfixposix
    enchant
  ];

  postPatch = ''
    # Patch the makefile to not run npm install (we do it ourselves)
    substituteInPlace makefile \
      --replace-fail 'NODE_SETUP ?= true' 'NODE_SETUP ?= false'

    # Patch cl-electron to check CL_ELECTRON_DIRECTORY environment variable first
    # This allows us to set the runtime directory for npm/electron
    substituteInPlace _build/cl-electron/source/core.lisp \
      --replace-fail \
        '(asdf:system-source-directory :cl-electron)' \
        '(or (uiop:getenv-pathname "CL_ELECTRON_DIRECTORY" :ensure-directory t)
                    (asdf:system-source-directory :cl-electron))'

    # Also patch the server-path to use the environment variable
    substituteInPlace _build/cl-electron/source/core.lisp \
      --replace-fail \
        '(asdf:system-relative-pathname :cl-electron "source/server.js")' \
        '(or (uiop:merge-pathnames* "source/server.js"
                                     (uiop:getenv-pathname "CL_ELECTRON_DIRECTORY" :ensure-directory t))
             (asdf:system-relative-pathname :cl-electron "source/server.js"))'
  '';

  configurePhase = ''
    runHook preConfigure

    export HOME=$TMPDIR

    # Set up npm dependencies for cl-electron
    cd _build/cl-electron
    export npm_config_cache=${clElectronNpmDeps}

    # Install npm packages without running scripts (offline)
    npm ci --ignore-scripts --offline

    # Fix shebangs in node_modules (they have /usr/bin/env)
    patchShebangs node_modules

    # Rebuild synchronous-socket native module against electron's headers
    # This is required because electron uses a different Node/V8 ABI
    cd node_modules/synchronous-socket
    ${nodejs}/bin/npx node-gyp rebuild \
      --nodedir=${electronHeaders} \
      --target=$(${electron}/bin/electron --version | sed 's/^v//') \
      --arch=x64 \
      --dist-url=https://electronjs.org/headers
    cd ../..

    cd ../..

    # Environment for ASDF/Lisp build
    export CL_SOURCE_REGISTRY="$PWD/_build//"
    export ASDF_OUTPUT_TRANSLATIONS="$PWD:$PWD"
    export PREFIX="$out"
    export NYXT_VERSION="${version}"

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # Build Nyxt with electron renderer
    make all \
      NYXT_RENDERER=electron \
      NYXT_SUBMODULES=true \
      NODE_SETUP=false

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mkdir -p $out/share/nyxt
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor/scalable/apps
    mkdir -p $out/lib/cl-electron

    # Install the binary
    install -Dm755 nyxt $out/bin/nyxt

    # Install assets
    cp -r assets/* $out/share/nyxt/ || true
    install -Dm644 assets/nyxt.desktop $out/share/applications/nyxt.desktop || true
    install -Dm644 assets/glyphs/nyxt.svg $out/share/icons/hicolor/scalable/apps/nyxt.svg || true

    # Install cl-electron runtime files (needed for electron)
    cp -r _build/cl-electron/node_modules $out/lib/cl-electron/
    cp _build/cl-electron/package.json $out/lib/cl-electron/
    cp -r _build/cl-electron/source $out/lib/cl-electron/

    # Point the npm electron package to our Nix electron
    mkdir -p $out/lib/cl-electron/node_modules/electron/dist
    ln -sf ${electron}/bin/electron $out/lib/cl-electron/node_modules/electron/dist/electron
    cat > $out/lib/cl-electron/node_modules/electron/index.js << EOF
    module.exports = '${electron}/bin/electron';
    EOF
    echo '${electron}/bin/electron' > $out/lib/cl-electron/node_modules/electron/path.txt

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/nyxt \
      --prefix PATH : ${
        lib.makeBinPath [
          xdg-utils
          xclip
          wl-clipboard
          nodejs
          electron
        ]
      } \
      --prefix LD_LIBRARY_PATH : "$LD_LIBRARY_PATH" \
      --set CL_ELECTRON_DIRECTORY "$out/lib/cl-electron/"
  '';

  # SBCL dumps a core image, stripping breaks it
  dontStrip = true;

  passthru = {
    inherit
      electron
      nodejs
      clElectronNpmDeps
      electronHeaders
      ;
  };

  meta = {
    description = "Infinitely extensible web browser (Electron backend)";
    homepage = "https://nyxt-browser.com";
    license = lib.licenses.bsd3;
    maintainers = [ ];
    platforms = lib.platforms.linux;
    mainProgram = "nyxt";
  };
}
