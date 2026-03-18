{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.nix-webapps;

  # Type definition for a web app
  webappType = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "URL of the web application";
        example = "https://mail.google.com";
      };

      icon = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Icon URL or local file path.
          Defaults to <baseUrl>/favicon.ico if not specified.
          For URL icons, nix will attempt to fetch with the provided sha (or fakeSha256 if not provided).
        '';
        example = "https://github.com/favicon.ico";
      };

      sha = mkOption {
        type = types.str;
        default = lib.fakeSha256;
        description = ''
          SHA256 hash of the icon file (required for URL icons).
          Defaults to fakeSha256 which will fail on first build and show the correct hash.
          Get the hash with: nix-prefetch-url <url>
        '';
        example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };

      browser = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Browser to use for this app. If not set, uses the global default.";
        example = "brave";
      };

      exec = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Custom exec command for launching the web app.

          This option allows you to override the default webapp-launcher behavior.
          Use cases include:
          - Using a different browser/profile not supported by webapp-launcher
          - Adding custom command-line flags or environment variables
          - Using proprietary or custom web app launchers (e.g., Spotify, Discord desktop apps)
          - Wrapping the launch command with additional tools (e.g., firejail, bubblewrap)

          If null, automatically generates a webapp-launcher script using the configured browser.
          The %U placeholder will be replaced with the URL being opened.
        '';
        example = "firejail --profile=webapp chromium --app=%U";
      };

      comment = mkOption {
        type = types.str;
        default = "";
        description = "Comment/description for the application. Defaults to app name if empty.";
        example = "My favorite web app";
      };

      mimeTypes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of MIME types this application handles";
        example = [ "x-scheme-handler/slack" ];
      };

      extraArgs = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = ''
          Extra command-line arguments to pass to the browser.
          Appended after --class and before --app.
          Useful for browser-specific flags like Ozone/Wayland, dark mode, feature flags, etc.
          If null, falls back to the global programs.nix-webapps.extraArgs setting.
        '';
        example = [
          "--enable-features=UseOzonePlatform,WebUIDarkMode"
          "--ozone-platform-hint=auto"
        ];
      };

      isolate = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          If true, launches the webapp with a dedicated user-data-dir to isolate
          cookies, sessions, and storage from other webapps and the main browser profile.
          If null, falls back to the global programs.nix-webapps.isolate setting.
        '';
      };
    };
  };

  # Extract base URL (protocol + domain) from a full URL
  # Example: "https://mail.google.com/path" -> "https://mail.google.com"
  getBaseUrl =
    url:
    let
      matches = builtins.match "(https?://[^/]+).*" url;
    in
    # If regex matches, return the captured group; otherwise return original URL
    if matches != null then builtins.head matches else url;

  # Get icon path for desktop file
  # If icon is a URL, fetch it at build time; otherwise use local path
  getIconPath =
    name: app:
    let
      iconSource = if app.icon != null then app.icon else "${getBaseUrl app.url}/favicon.ico";
      isRemote = hasPrefix "http://" iconSource || hasPrefix "https://" iconSource;
    in
    if isRemote then
      pkgs.fetchurl {
        url = iconSource;
        sha256 = app.sha; # Defaults to lib.fakeSha256
        name = "${name}-icon";
      }
    else
      iconSource; # Local file path

  # Generate .desktop file content
  makeDesktopFile =
    name: app:
    let
      iconPath = getIconPath name app;
      browser = if app.browser != null then app.browser else cfg.browser;

      # Extract domain for window class
      domain = builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] app.url;
      domainParts = builtins.split "/" domain;
      baseDomain = builtins.head domainParts;
      appClass = toLower "webapp.${browser}.${
        builtins.replaceStrings [ "." " " ] [ "-" "-" ] baseDomain
      }";

      resolvedExtraArgs = if app.extraArgs != null then app.extraArgs else cfg.extraArgs;
      extraArgsStr = optionalString (
        resolvedExtraArgs != [ ]
      ) " ${concatStringsSep " " resolvedExtraArgs}";
      shouldIsolate = if app.isolate != null then app.isolate else cfg.isolate;
      isolateStr = optionalString shouldIsolate " --user-data-dir=${config.xdg.configHome}/${appClass}";

      execCommand =
        if app.exec != null then
          app.exec
        else
          ''${browser} --new-window --class="${appClass}"${extraArgsStr}${isolateStr} --app="${app.url}"'';
      mimeTypeStr = optionalString (
        app.mimeTypes != [ ]
      ) "MimeType=${concatStringsSep ";" app.mimeTypes};\n";
      iconStr = "Icon=${iconPath}\n";
    in
    pkgs.writeText "${name}.desktop" ''
      [Desktop Entry]
      Version=1.5
      Name=${name}
      Comment=${if app.comment != "" then app.comment else name}
      Exec=${execCommand}
      Terminal=false
      Type=Application
      StartupWMClass=${appClass}
      ${iconStr}StartupNotify=true
      ${mimeTypeStr}'';

in
{
  options.programs.nix-webapps = {
    enable = mkEnableOption "Nix Web Applications Manager";

    apps = mkOption {
      type = types.attrsOf webappType;
      default = { };
      description = "Web applications to manage";
      example = literalExpression ''
        {
          gmail = {
            url = "https://mail.google.com";
            comment = "Gmail Web App";
            # icon will be auto-fetched from https://mail.google.com/favicon.ico
          };
          github = {
            url = "https://github.com";
            # icon auto-fetched
          };
        }
      '';
    };

    browser = mkOption {
      type = types.str;
      description = "Default browser to use for all web applications.";
      example = "brave";
    };

    isolate = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If true, all webapps will launch with a dedicated user-data-dir to isolate
        cookies, sessions, and storage. Can be overridden per-app.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra command-line arguments passed to the browser for all webapps.
        Per-app extraArgs override this entirely when set.
      '';
      example = [
        "--enable-features=UseOzonePlatform"
        "--ozone-platform-hint=auto"
      ];
    };
  };

  config = mkIf cfg.enable {
    # Generate .desktop files for each web app
    xdg.dataFile = mapAttrs' (
      name: app:
      nameValuePair "applications/${name}.desktop" {
        source = makeDesktopFile name app;
      }
    ) cfg.apps;
  };
}
