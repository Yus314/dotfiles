{
  lib,
  writeShellScriptBin,
  bash,
  yq-go,
  terraform,
  coreutils,
  findutils,
  util-linux,
}:

writeShellScriptBin "tf-wrapper" ''
  #!${bash}/bin/bash

  # 依存関係のパス設定
  export PATH="${
    lib.makeBinPath [
      yq-go
      terraform
      coreutils
      findutils
      util-linux
    ]
  }:$PATH"

  # メインスクリプト実行
  ${builtins.readFile ./tf-wrapper.sh}
''
// {
  meta = with lib; {
    description = "Terraform wrapper with universal OCI backend support";
    homepage = "https://github.com/Yus314/dotfiles";
    license = licenses.mit;
    maintainers = [ "Yus314" ];
    platforms = platforms.unix;
  };
}
