{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.nix-webapps;

  # Supported browser types
  browserType = types.enum [
    "brave"
    "chromium-browser"
    "edge"
    "firefox"
    "floorp"
    "google-chrome"
    "librewolf"
    "mullvad"
    "thorium"
    "vivaldi"
    "waterfox"
    "zen"
    "zen-beta"
  ];

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
        type = types.nullOr browserType;
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

      firefoxPwaId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Firefox PWA Site ID (ULID) for launching with firefoxpwa (Optional if pwa.enable is true)";
        example = "01GQD9S60... (13-26 character ULID)";
      };

      pwa = mkOption {
        default = { };
        description = "Declarative Firefox PWA configuration";
        type = types.submodule {
          options = {
            enable = mkEnableOption "declarative Firefox PWA support";

            manifest = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "URL to the web app manifest. Defaults to <url>/manifest.json";
            };

            profile = mkOption {
              type = types.str;
              default = "default";
              description = "Firefox profile to use/install into";
            };
          };
        };
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
      appClass = "WebApp-${builtins.replaceStrings [ "." ] [ "-" ] baseDomain}";

      # Browser categorization by engine
      isChromiumBased = builtins.elem browser [
        "brave"
        "chromium-browser"
        "edge"
        "google-chrome"
        "thorium"
        "vivaldi"
      ];
      isFirefoxBased = builtins.elem browser [
        "firefox"
        "floorp"
        "librewolf"
        "mullvad"
        "waterfox"
        "zen"
        "zen-beta"
      ];

      execCommand =
        if app.exec != null then
          app.exec
        else if browser == null then
          throw ''
            Web app "${name}" requires a browser to be specified.
            Either set:
              - programs.nix-webapps.browser (global default), or
              - programs.nix-webapps.apps.${name}.browser (per-app), or
              - programs.nix-webapps.apps.${name}.exec (custom launcher)
          ''
        else if isChromiumBased then
          ''${browser} --new-window --class="${appClass}" --app="${app.url}"''
        else if isFirefoxBased && app.firefoxPwaId != null then
          "${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${app.firefoxPwaId}"
        else if isFirefoxBased then
          ''${browser} --new-window --class "${appClass}" "${app.url}"''
        else
          throw "Unsupported browser: ${browser}";
      mimeTypeStr = optionalString (
        app.mimeTypes != [ ]
      ) "MimeType=${concatStringsSep ";" app.mimeTypes};\n";
      iconStr = "Icon=${iconPath}\n";
    in
    pkgs.writeText "${name}.desktop" ''
      [Desktop Entry]
      Version=1.0
      Name=${name}
      Comment=${if app.comment != "" then app.comment else name}
      Exec=${execCommand}
      Terminal=false
      Type=Application
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
      type = types.nullOr browserType;
      default = null;
      description = ''
        Default browser to use for all web applications.
        If not set, must specify browser per-app.
      '';
      example = "brave";
    };

    firefox = {
      enablePwa = mkEnableOption "Firefox PWA support (installs firefoxpwa)";
    };
  };

  config = mkIf cfg.enable {
    home.packages = mkIf cfg.firefox.enablePwa (with pkgs; [ firefoxpwa ]);

    # Generate .desktop files for each web app
    xdg.dataFile = mapAttrs' (
      name: app:
      let
        # Define the launcher script
        pwaLauncher = pkgs.writeShellScriptBin "nix-webapps-launch-pwa-${name}" ''
          set -euo pipefail
          
          # Fix PATH to ensure we have grep, awk, etc.
          export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gawk ]}:$PATH"

          LOG_FILE="/tmp/nix-webapps-${name}.log"
          echo "[$(date)] Launching ${name}..." >> "$LOG_FILE"
          
          # Redirect stderr to log for debugging
          exec 2>>"$LOG_FILE"

          APP_NAME="${name}"
          APP_URL="${app.url}"
          MANIFEST_URL="${if app.pwa.manifest != null then app.pwa.manifest else "${app.url}/manifest.json"}"
          PROFILE="${app.pwa.profile}"
          
          echo "Checking PWA for URL: $APP_URL" >> "$LOG_FILE"

          # Check if specific firefoxpwa ID is provided manually, otherwise try to find/install
          SITE_ID="${if app.firefoxPwaId != null then app.firefoxPwaId else ""}"

          if [ -z "$SITE_ID" ]; then
            # Find existing by Manifest URL
            # We use || true to ensure grep failure doesn't crash the script immediately due to pipefail/set -e
            # but we need to handle the empty output case.
            EXISTING_ID=$(${pkgs.firefoxpwa}/bin/firefoxpwa site list | grep "$MANIFEST_URL" | awk '{print $1}' | head -n1 || true)
            
            if [ -n "$EXISTING_ID" ]; then
              echo "Found existing installation: $EXISTING_ID" >> "$LOG_FILE"
              SITE_ID="$EXISTING_ID"
            else
              # Install if not found
              echo "Installing PWA for $APP_NAME..." >> "$LOG_FILE"
              # We use a temporary icon file if needed, but for now let firefoxpwa fetch it
              ${pkgs.firefoxpwa}/bin/firefoxpwa site install "$MANIFEST_URL" --name "$APP_NAME" --profile "$PROFILE" --no-system-integration >> "$LOG_FILE" 2>&1
              
              # Get the ID of the just installed site
              SITE_ID=$(${pkgs.firefoxpwa}/bin/firefoxpwa site list | grep "$MANIFEST_URL" | awk '{print $1}' | head -n1)
              echo "Installed with ID: $SITE_ID" >> "$LOG_FILE"
            fi
          fi

          if [ -n "$SITE_ID" ]; then
            echo "Launching site ID: $SITE_ID" >> "$LOG_FILE"
            exec ${pkgs.firefoxpwa}/bin/firefoxpwa site launch "$SITE_ID"
          else
            echo "Failed to resolve or install PWA site ID." >> "$LOG_FILE"
            exit 1
          fi
        '';
      in
      nameValuePair "applications/${name}.desktop" {
        source =
          if app.pwa.enable then
            makeDesktopFile name (app // { exec = "${pwaLauncher}/bin/nix-webapps-launch-pwa-${name}"; })
          else
            makeDesktopFile name app;
      }
    ) cfg.apps;
  };
}
