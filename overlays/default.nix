{ inputs }:
{
  kakoune-updated = final: prev: {
    kakoune-unwrapped = prev.kakoune-unwrapped.overrideAttrs (oldAttrs: {
      version = "unstable-2025-06-18";
      src = prev.fetchFromGitHub {
        owner = "mawww";
        repo = "kakoune";
        rev = "50cdb754fb9cc1d8af79285cf6076330de02de20";
        hash = "sha256-iLq27vI8rMttUoONnYxWjn1SLk1IJ3yva9FqApZ0diI=";
      };
    });
  };

  fcitx5-updated = final: prev: {
    fcitx5 = prev.fcitx5.overrideAttrs (oldAttrs: rec {
      version = "5.1.14";
      src = prev.fetchFromGitHub {
        owner = "fcitx";
        repo = "fcitx5";
        rev = version;
        hash = "sha256-wLJZyoWjf02+m8Kw+IcfbZY2NnjMGtCWur2+w141eS4=";
      };
    });
  };
}
