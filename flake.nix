{
  description = "Declarative web application manager for Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, treefmt-nix }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Home Manager module
      homeManagerModules.default = import ./webapp-manager.nix;
      homeManagerModules.nix-webapps = import ./webapp-manager.nix;

      # Formatter for each system
      formatter = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.nixpkgs-fmt.enable = true;
            programs.prettier.enable = true;
          };
        in
        treefmtEval.config.build.wrapper
      );
    };
}
