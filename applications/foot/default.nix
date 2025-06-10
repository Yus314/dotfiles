{ pkgs, ... }:
{
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Bizin Gothic Discord NF:size=18";
      };
    };
  };
}
