{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.nix-webapps;

  webappType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.strMatching "https?://.+";
        description = "URL of the web application (must start with http:// or https://)";
        example = "https://mail.google.com";
      };

      icon = lib.mkOption {
        type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
        default = null;
        description = ''
          Icon for the application. Accepts:
          - A remote URL (requires iconHash)
          - A local file path
          - null to auto-fetch from <baseUrl>/favicon.ico (requires iconHash)
          If both icon and iconHash are null, no icon is set.
        '';
        example = "https://github.com/favicon.ico";
      };

      iconHash = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SHA256 hash of the icon file. Required when icon is a remote URL or null (auto-fetch).
          Ignored for local file paths. Use `nix-prefetch-url --type sha256 <url> | nix hash to-sri --type sha256`
          to obtain the SRI-format hash.
        '';
        example = "sha256-LuQyN9GWEAIQ8Xhue3O1fNFA9gE8Byxw29/9npvGlfg=";
      };

      browser = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Browser to use for this app. If not set, uses the global default.";
        example = "brave";
      };

      exec = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
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

      comment = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Comment/description for the application. Defaults to app name if empty.";
        example = "My favorite web app";
      };

      mimeTypes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of MIME types this application handles";
        example = [ "x-scheme-handler/slack" ];
      };

      extraArgs = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
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

      isolate = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          If true, launches the webapp with a dedicated user-data-dir to isolate
          cookies, sessions, and storage from other webapps and the main browser profile.
          If null, falls back to the global programs.nix-webapps.isolate setting.
        '';
      };
    };
  };

  parseUrl =
    url:
    let
      protocol =
        let
          m = builtins.match "(https?)://.*" url;
        in
        if m != null then builtins.head m else null;
      base = builtins.head (builtins.match "(https?://[^/]+).*" url);
      domainParts = builtins.split "/" (builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] url);
      host = builtins.head domainParts;
    in
    {
      inherit protocol base host;
    };

  isRemoteUrl =
    icon:
    let
      str = toString icon;
    in
    lib.hasPrefix "http://" str || lib.hasPrefix "https://" str;

  resolveIcon =
    name: app:
    if app.icon != null && isRemoteUrl app.icon then
      pkgs.fetchurl {
        url = toString app.icon;
        sha256 = app.iconHash;
        name = "${name}-icon";
      }
    else if app.icon != null then
      toString app.icon
    else if app.iconHash != null then
      pkgs.fetchurl {
        url = "${(parseUrl app.url).base}/favicon.ico";
        sha256 = app.iconHash;
        name = "${name}-favicon.ico";
      }
    else
      null;

  withDefault = appAttr: globalAttr: if appAttr != null then appAttr else globalAttr;

  makeAppClass =
    browser: url:
    let
      inherit (parseUrl url) host;
    in
    lib.toLower "webapp.${browser}.${builtins.replaceStrings [ "." " " ] [ "-" "-" ] host}";

  makeExec =
    _name: app:
    let
      browser = withDefault app.browser cfg.browser;
      resolvedExtraArgs = withDefault app.extraArgs cfg.extraArgs;
      extraArgsStr = lib.optionalString (
        resolvedExtraArgs != [ ]
      ) " ${lib.concatStringsSep " " resolvedExtraArgs}";
      shouldIsolate = withDefault app.isolate cfg.isolate;
      appClass = makeAppClass browser app.url;
      isolateStr = lib.optionalString shouldIsolate " --user-data-dir=${config.xdg.configHome}/${appClass}";
    in
    if app.exec != null then
      app.exec
    else
      ''${browser} --new-window --class="${appClass}"${extraArgsStr}${isolateStr} --app="${app.url}"'';

  makeDesktopFile =
    name: app:
    let
      iconPath = resolveIcon name app;
      execCommand = makeExec name app;
      browser = withDefault app.browser cfg.browser;
      appClass = makeAppClass browser app.url;
      mimeTypeStr = lib.optionalString (
        app.mimeTypes != [ ]
      ) "MimeType=${lib.concatStringsSep ";" app.mimeTypes};\n";
      iconStr = lib.optionalString (iconPath != null) "Icon=${iconPath}\n";
    in
    pkgs.writeText "${name}.desktop" ''
      [Desktop Entry]
      Version=1.0
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
    enable = lib.mkEnableOption "Nix Web Applications Manager";

    apps = lib.mkOption {
      type = lib.types.attrsOf webappType;
      default = { };
      description = "Web applications to manage";
      example = lib.literalExpression ''
        {
          gmail = {
            url = "https://mail.google.com";
            comment = "Gmail Web App";
            iconHash = "sha256-...";
          };
          github = {
            url = "https://github.com";
            iconHash = "sha256-...";
          };
          custom-app = {
            url = "https://example.com";
            icon = ./icons/custom.png;
          };
        }
      '';
    };

    browser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default browser to use for all web applications. Required if any app omits `exec` and `browser`.";
      example = "brave";
    };

    isolate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        If true, all webapps will launch with a dedicated user-data-dir to isolate
        cookies, sessions, and storage. Can be overridden per-app.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
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

  config = lib.mkIf cfg.enable {
    assertions =
      let
        needsBrowser = lib.filterAttrs (_name: app: app.exec == null) cfg.apps;
      in
      lib.mapAttrsToList (name: app: {
        assertion = !(app.icon != null && isRemoteUrl app.icon) || app.iconHash != null;
        message = "nix-webapps: '${name}' requires iconHash when icon is a remote URL";
      }) cfg.apps
      ++ lib.mapAttrsToList (name: app: {
        assertion = (parseUrl app.url).protocol != null;
        message = "nix-webapps: '${name}' url must start with http:// or https://";
      }) cfg.apps
      ++ lib.mapAttrsToList (name: _app: {
        assertion = cfg.browser != null;
        message = "nix-webapps: global `browser` is required when any app omits `exec` ('${name}' does)";
      }) needsBrowser;

    xdg.dataFile = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "applications/${name}.desktop" {
        source = makeDesktopFile name app;
      }
    ) cfg.apps;
  };
}
