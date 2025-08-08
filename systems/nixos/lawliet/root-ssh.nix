# Root SSH configuration for distributed builds
{ config, pkgs, ... }:
{
  # Root SSH client configuration via environment.etc
  environment.etc."ssh/ssh_config.d/90-root-distributed-builds.conf" = {
    text = ''
      # Distributed build hosts configuration for root user
      Host ryuk
        Hostname test.mdip2home.com
        User kaki
        Port 22
        ProxyCommand ${pkgs.cloudflared}/bin/cloudflared access ssh --hostname test.mdip2home.com
        IdentityFile /root/.ssh/id_ed25519
        StrictHostKeyChecking accept-new
        ConnectTimeout 10
        ControlMaster auto
        ControlPath ~/.ssh/master-%r@%n:%p
        ControlPersist 10m
      
      Host rem
        Hostname sub.mdip2home.com
        User kaki
        Port 22
        ProxyCommand ${pkgs.cloudflared}/bin/cloudflared access ssh --hostname sub.mdip2home.com
        IdentityFile /root/.ssh/id_ed25519
        StrictHostKeyChecking accept-new
        ConnectTimeout 10
        ControlMaster auto
        ControlPath ~/.ssh/master-%r@%n:%p
        ControlPersist 10m
    '';
    mode = "0644";
  };

  # Include the ssh_config.d directory in system-wide SSH config
  programs.ssh.extraConfig = ''
    # Include root-specific configurations for distributed builds
    Include /etc/ssh/ssh_config.d/*.conf
  '';

  # SOPS secret for root SSH private key only
  sops.secrets."root-ssh-key" = {
    sopsFile = ../../../secrets/root-ssh.yaml;
    path = "/root/.ssh/id_ed25519";
    owner = "root";
    group = "root";
    mode = "0600";
  };
}