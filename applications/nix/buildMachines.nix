{
  nix = {
    distributedBuilds = false;

    extraOptions = ''
      builders-use-substitutes = true
    '';

    buildMachines = [ ];
  };
}
