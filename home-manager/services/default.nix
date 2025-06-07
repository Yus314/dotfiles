{ pkgs, emacsPkg }:
let
  emacs = import ./emacs { inherit pkgs emacsPkg; };
in
[ emacs ]
