{
  programs.offlineimap = {
    enable = true;
    extraConfig = {
      general = {
        accounts = "Gmail";
        maxsyncaccounts = 3;
      };
    };
  };
  accounts.email.accounts = {
    Gmail = {
      primary = true;
      address = "shizhaoyoujie@gmail.com";
      userName = "shizhaoyoujie@gmail.com";
      realName = "Yusuke Kakinuma";
      flavor = "gmail.com";
      offlineimap = {
        enable = true;
        extraConfig = {
          account = {
            maxconnections = 1;
            autorefresh = 10;
            quick = 10;
            postsynchook = "mu index";
            utf8foldername = "yes";
          };
          local = {
            type = "Maildir";
          };
          remote = {
            type = "IMAP";
            remotehost = "imap.gmail.com";
            remotepass = "oewwpzyosmuncdft";
            ssl = true;
          };
        };
      };
    };
  };
}
