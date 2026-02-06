{
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) org-babel;
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  sources = pkgs.callPackage ../../sources/generated.nix { };
  emacsPkg = import ./emacspkg {
    inherit pkgs sources;
  };
in
{
  programs.emacs = {
    enable = true;
    package = emacsPkg.emacs-unstable;
  };
  xdg.configFile."emacs/init.el".text = tangle (builtins.readFile ./elisp/init.org);
  xdg.configFile."emacs/early-init.el".text = tangle (builtins.readFile ./elisp/early-init.org);
  xdg.configFile."emacs/.authinfo.gpg".source = ./.authinfo.gpg;
  home = {
    packages = with pkgs; [
      nil
      nixfmt
      #rust-analyzer
      basedpyright
      pyright
      ruff
      tinymist
      terraform-ls
      # Common Lisp
      sbcl
    ];
  };
}
