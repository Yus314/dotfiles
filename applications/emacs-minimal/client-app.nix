{
  pkgs,
  emacsFrame,
  emacsPackage,
}:
let
  bundleName = "Emacs Client";
  bundleExecutable = "EmacsClient";
  bundleIdentifier = "dev.yus314.emacs-client";
  infoPlist = pkgs.writeText "emacs-client-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleExecutable</key>
      <string>${bundleExecutable}</string>
      <key>CFBundleIconFile</key>
      <string>Emacs.icns</string>
      <key>CFBundleIdentifier</key>
      <string>${bundleIdentifier}</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>${bundleName}</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
    </dict>
    </plist>
  '';
in
pkgs.runCommand "emacs-client-app"
  {
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
  }
  ''
    app="$out/Applications/${bundleName}.app/Contents"
    mkdir -p "$app/MacOS" "$app/Resources"
    makeBinaryWrapper ${emacsFrame}/bin/emacs-frame "$app/MacOS/${bundleExecutable}"
    cp ${infoPlist} "$app/Info.plist"
    cp ${emacsPackage}/Applications/Emacs.app/Contents/Resources/Emacs.icns \
      "$app/Resources/Emacs.icns"
  ''
