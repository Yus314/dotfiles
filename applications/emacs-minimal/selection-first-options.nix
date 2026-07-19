{ lib, ... }:
{
  options.programs.emacs.selectionFirst.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable the Meow-independent selection-first frontend.  When disabled,
      the minimal profile keeps Meow as the modal owner for shadow rollout and
      immediate declarative rollback.
    '';
  };
}
