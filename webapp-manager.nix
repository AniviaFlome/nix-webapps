{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.nix-webapps;

  # Type definition for a web app
  webappType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        description = "URL of the web application";
        example = "https://mail.google.com";
      };

      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Icon URL or local file path.
          Defaults to <baseUrl>/favicon.ico if not specified.
          Remote icons are fetched at activation time and cached in $XDG_CACHE_HOME/nix-webapps/icons/.
        '';
        example = "https://github.com/favicon.ico";
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

  # Extract base URL (protocol + domain) from a full URL
  # Example: "https://mail.google.com/path" -> "https://mail.google.com"
  getBaseUrl =
    url:
    let
      matches = builtins.match "(https?://[^/]+).*" url;
    in
    if matches != null then builtins.head matches else url;

  # Determine icon source: explicit icon URL/path or auto-derived favicon URL
  getIconSource = app: if app.icon != null then app.icon else "${getBaseUrl app.url}/favicon.ico";

  # Check if a URL is a remote HTTP/HTTPS URL
  isRemoteUrl = url: lib.hasPrefix "http://" url || lib.hasPrefix "https://" url;

  iconCacheDir = "${config.xdg.cacheHome}/nix-webapps/icons";

  # Get icon path for desktop file
  # Remote icons are fetched at activation time and cached locally; local paths are used as-is
  getIconPath =
    name: app:
    let
      iconSource = getIconSource app;
    in
    if isRemoteUrl iconSource then "${iconCacheDir}/${name}-icon" else iconSource;

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
      appClass = lib.toLower "webapp.${browser}.${
        builtins.replaceStrings [ "." " " ] [ "-" "-" ] baseDomain
      }";

      resolvedExtraArgs = if app.extraArgs != null then app.extraArgs else cfg.extraArgs;
      extraArgsStr = lib.optionalString (
        resolvedExtraArgs != [ ]
      ) " ${lib.concatStringsSep " " resolvedExtraArgs}";
      shouldIsolate = if app.isolate != null then app.isolate else cfg.isolate;
      isolateStr = lib.optionalString shouldIsolate " --user-data-dir=${config.xdg.configHome}/${appClass}";

      execCommand =
        if app.exec != null then
          app.exec
        else
          ''${browser} --new-window --class="${appClass}"${extraArgsStr}${isolateStr} --app="${app.url}"'';
      mimeTypeStr = lib.optionalString (
        app.mimeTypes != [ ]
      ) "MimeType=${lib.concatStringsSep ";" app.mimeTypes};\n";
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
            # icon will be auto-fetched from https://mail.google.com/favicon.ico
          };
          github = {
            url = "https://github.com";
            # icon auto-fetched
          };
        }
      '';
    };

    browser = lib.mkOption {
      type = lib.types.str;
      description = "Default browser to use for all web applications.";
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
    # Generate .desktop files for each web app
    xdg.dataFile = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "applications/${name}.desktop" {
        source = makeDesktopFile name app;
      }
    ) cfg.apps;

    # Fetch remote icons at activation time; sync cache to match current config
    home.activation.fetchWebappIcons = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        remoteApps = lib.filterAttrs (
          _name: app:
          isRemoteUrl (getIconSource app)
        ) cfg.apps;

        expectedList = lib.concatStringsSep " " (lib.mapAttrsToList (name: _: ''"${name}-icon"'') remoteApps);

        fetchCmds = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: app:
            let
              iconSource = getIconSource app;
            in
            ''
              if [ ! -f "${iconCacheDir}/${name}-icon" ] || [ ! -f "${iconCacheDir}/${name}-icon.url" ] || [ "$(cat "${iconCacheDir}/${name}-icon.url")" != "${iconSource}" ]; then
                if ${pkgs.curl}/bin/curl -fsL --max-time 10 -o "${iconCacheDir}/${name}-icon" "${iconSource}"; then
                  printf '%s' "${iconSource}" > "${iconCacheDir}/${name}-icon.url"
                else
                  echo >&2 "WARNING: Failed to fetch icon for '${name}' from ${iconSource}"
                  rm -f "${iconCacheDir}/${name}-icon"
                fi
              fi
            ''
          ) remoteApps
        );
      in
      ''
        mkdir -p "${iconCacheDir}"

        # Remove orphaned icons not in current config
        EXPECTED_ICONS=(${expectedList})
        for f in "${iconCacheDir}"/*-icon; do
          [ -e "$f" ] || continue
          basename="$(basename "$f")"
          found=0
          for expected in "''${EXPECTED_ICONS[@]}"; do
            [ "$basename" = "$expected" ] && found=1 && break
          done
          [ "$found" = 0 ] && rm -f "$f" "$f.url"
        done

        ${fetchCmds}
      ''
    );
  };
}
