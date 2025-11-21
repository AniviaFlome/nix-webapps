# Test Configuration for Web App Manager

# This is a minimal test configuration to verify the module works
{ config, pkgs, ... }:

{
  imports = [
    ./webapp-manager.nix
  ];

  programs.webappManager = {
    enable = true;

    apps = {
      # Test with a simple web app
      github = {
        url = "https://github.com";
        icon = "https://github.githubassets.com/favicons/favicon.png";
        comment = "GitHub";
      };
    };
  };
}
