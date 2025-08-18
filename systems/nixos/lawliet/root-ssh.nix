# Root SSH configuration for distributed builds
{ config, pkgs, ... }:
{
  # Root-specific SSH configuration (not system-wide)
  # This creates /root/.ssh/config directly for root user only
  system.activationScripts.rootSshConfig = {
    text = ''
      mkdir -p /root/.ssh
      cat > /root/.ssh/config <<'EOF'
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
      EOF

      # Set proper permissions for SSH config
      chmod 600 /root/.ssh/config
      chown root:root /root/.ssh/config
    '';
    deps = [ ];
  };

  # SOPS secret for root SSH private key only
  sops.secrets."root-ssh-key" = {
    sopsFile = ../../../secrets/root-ssh.yaml;
    path = "/root/.ssh/id_ed25519";
    owner = "root";
    group = "root";
    mode = "0600";
  };
}
