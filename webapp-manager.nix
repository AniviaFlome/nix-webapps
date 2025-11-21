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
        description = "Icon URL or local file path. URLs will be downloaded at activation time (not build time). If null, automatically fetches favicon from website.";
        example = "./icons/myapp.png";
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

  # Helper function to get icon path/URL for an app
  # Returns either a local path or URL (download happens in activation script)
  getIconPath = name: app:
    if app.icon == null then
    # Auto-generate favicon URL from base URL
      "${getBaseUrl app.url}/favicon.ico"
    else if isUrl app.icon then
    # Return URL as-is, download happens in activation
      app.icon
    else
    # Local file path
      app.icon;

  # Generate .desktop file content
  makeDesktopFile = name: app:
    let
      iconPath = "$HOME/.local/share/applications/icons/${name}.png";
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
    in
    pkgs.writeText "${name}.desktop" ''
      [Desktop Entry]
      Version=1.0
      Name=${name}
      Comment=${if app.comment != "" then app.comment else name}
      Exec=${execCommand}
      Terminal=false
      Type=Application
      Icon=${iconPath}
      StartupNotify=true
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

    # Ensure the icons directory exists and download/copy icons
    home.activation.webappIcons = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p $HOME/.local/share/applications/icons

      ${concatStringsSep "\n" (mapAttrsToList (name: app:
        let
          iconRef = getIconPath name app;
          isIconUrl = isUrl iconRef;
        in
        if isIconUrl then
          # Download icon from URL
          ''
            if [[ -z "$DRY_RUN" ]]; then
              ${pkgs.curl}/bin/curl -sL "${iconRef}" -o "$HOME/.local/share/applications/icons/${name}.png" || echo "Warning: Failed to download icon for ${name}"
            fi
          ''
        else
          # Copy local icon file
          ''
            $DRY_RUN_CMD cp -f ${iconRef} $HOME/.local/share/applications/icons/${name}.png
          ''
      ) cfg.apps)}
    '';
  };
}
