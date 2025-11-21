{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.nix-webapps;

  # Browser type definition
  browserType = types.enum [ "firefox" "brave" "chromium" "zen" "vivaldi" "edge" ];

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
        description = "Icon URL or local file path. If URL, must also provide iconSha256.";
        example = "https://github.com/favicon.ico";
      };

      iconSha256 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SHA256 hash of the icon file (required for URL icons). Get with: nix-prefetch-url <url>";
        example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };

      browser = mkOption {
        type = types.nullOr browserType;
        default = null;
        description = "Browser to use for this app. If null, uses defaultBrowser.";
        example = "brave";
      };

      exec = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom exec command. If null, uses the webapp-launcher with configured browser.";
        example = "custom-browser-launcher %U";
      };

      comment = mkOption {
        type = types.str;
        default = "";
        description = "Comment/description for the application";
        example = "My favorite web app";
      };

      mimeTypes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of MIME types this application handles";
        example = [ "x-scheme-handler/slack" ];
      };
    };
  };

  # Helper function to determine if icon is a URL
  isUrl = str: hasPrefix "http://" str || hasPrefix "https://" str;

  # Helper function to extract base URL from a full URL
  getBaseUrl = url:
    let
      # Extract protocol and domain from URL
      matches = builtins.match "(https?://[^/]+).*" url;
    in
    if matches != null then builtins.head matches else url;

  # Helper function to get icon path for desktop file
  getIconPath = name: app:
    let
      # Determine the icon URL to use
      iconUrl = if app.icon == null then "${getBaseUrl app.url}/favicon.ico" else app.icon;
      # Determine if it's a URL
      isIconUrl = isUrl iconUrl;
      # Use provided SHA or fake SHA for auto-fetched favicons
      iconSha =
        if app.iconSha256 != null then
          app.iconSha256
        else if app.icon == null then
        # Auto-fetch favicon: use fake SHA which will fail with real hash
          lib.fakeSha256
        else
          null;
    in
    if isIconUrl && iconSha != null then
    # Download icon at build time with fetchurl
      pkgs.fetchurl
        {
          url = iconUrl;
          sha256 = iconSha;
          name = "${name}-icon";
        }
    else if isIconUrl then
      null  # URL without SHA256 - skip icon
    else if iconUrl != null then
    # Local file path
      iconUrl
    else
      null;

  # Generate .desktop file content
  makeDesktopFile = name: app:
    let
      iconPath = getIconPath name app;
      # Use per-app browser if specified, otherwise use defaultBrowser
      browser = if app.browser != null then app.browser else cfg.browser;
      # Use webapp-launcher generator if no custom exec is provided
      execCommand =
        if app.exec != null then
          app.exec
        else
          let
            launcher = pkgs.callPackage ./webapp-launcher.nix {
              inherit browser;
              url = app.url;
              appName = name;
            };
          in
          "${launcher}/bin/webapp-launcher-${name}";
      mimeTypeStr =
        if app.mimeTypes != [ ] then
          "MimeType=${concatStringsSep ";" app.mimeTypes};\n"
        else
          "";
      iconStr =
        if iconPath != null then
          "Icon=${iconPath}\n"
        else
          "";
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
      type = browserType;
      default = "firefox";
      description = "Default browser to use for all web applications";
      example = "brave";
    };
  };

  config = mkIf cfg.enable {
    # Generate .desktop files for each web app
    xdg.dataFile = mapAttrs'
      (name: app:
        nameValuePair "applications/${name}.desktop" {
          source = makeDesktopFile name app;
        }
      )
      cfg.apps;
  };
}
