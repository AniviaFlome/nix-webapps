{
  description = "Declarative web application manager for Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);

      webappModule = import ./webapp-manager.nix;
      inherit (nixpkgs) lib;

      # Evaluate the module against a config, returning the merged config.
      # Stubs assertions + xdg so the module works outside a real HM eval.
      evalConfig =
        conf:
        (lib.evalModules {
          modules = [
            webappModule
            {
              options.assertions = lib.mkOption {
                type = lib.types.listOf lib.types.unspecified;
                default = [ ];
              };
              options.xdg = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };
              config.xdg.configHome = lib.mkDefault "/home/test/.config";
            }
            { programs.nix-webapps = conf; }
          ];
        }).config;

      failedAssertions = cfg: lib.filter (a: !a.assertion) cfg.assertions;

      # 1. Valid config: evaluates, produces desktop entry, no failed assertions
      valid = evalConfig {
        enable = true;
        browser = "brave";
        apps.gmail.url = "https://mail.google.com";
      };
      validKeys = builtins.attrNames valid.xdg.dataFile;
      validFailed = failedAssertions valid;

      # 2. Missing iconHash for remote icon -> assertion failure
      badIcon = evalConfig {
        enable = true;
        browser = "brave";
        apps.bad = {
          url = "https://example.com";
          icon = "https://example.com/icon.png";
        };
      };
      badIconFailed = failedAssertions badIcon;

      # 3. App omits exec+browser while global browser is null -> assertion failure
      badBrowser = evalConfig {
        enable = true;
        browser = null;
        apps.noname = {
          url = "https://example.com";
        };
      };
      badBrowserFailed = failedAssertions badBrowser;

      moduleEvalPassed =
        builtins.length validKeys == 1
        && builtins.length validFailed == 0
        && builtins.length badIconFailed == 1
        && lib.hasInfix "requires iconHash" (builtins.head badIconFailed).message
        && builtins.length badBrowserFailed == 1
        && lib.hasInfix "browser" (builtins.head badBrowserFailed).message;
    in
    {
      formatter = eachSystem (pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);

      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.check self;

        # Pure-Nix module eval check. Succeeds (produces output) only when all
        # test assertions pass; fails the build otherwise.
        moduleEval =
          pkgs.runCommand "nix-webapps-module-eval"
            {
              results = builtins.toJSON {
                validKeyCount = builtins.length validKeys;
                validFailedCount = builtins.length validFailed;
                badIconFailedCount = builtins.length badIconFailed;
                badIconMessage = (builtins.head badIconFailed).message or "";
                badBrowserFailedCount = builtins.length badBrowserFailed;
                badBrowserMessage = (builtins.head badBrowserFailed).message or "";
                passed = moduleEvalPassed;
              };
            }
            ''
              echo "Module eval check results:" >&2
              echo "$results" | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value)"' >&2
              ${lib.optionalString moduleEvalPassed "touch $out"}
              ${lib.optionalString (!moduleEvalPassed) "exit 1"}
            '';
      });

      homeManagerModules = {
        default = webappModule;
        nix-webapps = self.homeManagerModules.default;
      };
    };
}
