# Example Home Manager Configuration for Web App Manager

To use this module, add it to your Home Manager imports and configure your web apps.

## Import the Module

```nix
# In your home.nix or wherever you configure Home Manager
{ config, pkgs, ... }:

{
imports = [
./webapp-manager.nix  # Adjust path as needed
];

# ... rest of your config
}
```

## Example Configuration

```nix
programs.nix-webapps = {
enable = true;

apps = {
# Simple web app - icon automatically fetched from favicon
gmail = {
url = "https://mail.google.com";
comment = "Gmail Web App";
};

# With custom icon URL
github = {
url = "https://github.com";
icon = "https://github.githubassets.com/favicons/favicon.png";
comment = "GitHub";
};

# Example with local icon file
notion = {
url = "https://notion.so";
icon = ./icons/notion.png;  # Local file path
comment = "Notion Workspace";
};

# Example with custom exec command
slack = {
url = "https://slack.com";
icon = "https://a.slack-edge.com/80588/marketing/img/meta/favicon-32.png";
exec = "chromium --app=%U";  # Use Chromium instead
comment = "Slack";
};

# Example with MIME types for protocol handling
discord = {
url = "https://discord.com/app";
# No icon specified - will fetch favicon automatically
mimeTypes = [ "x-scheme-handler/discord" ];
comment = "Discord";
};

# Example combining custom exec and MIME types
zoom = {
url = "https://zoom.us";
icon = "https://st1.zoom.us/static/6.3.0/image/new/ZoomLogo.png";
exec = "firefox --new-window --class WebApp-Zoom %U";
mimeTypes = [ "x-scheme-handler/zoommtg" "x-scheme-handler/zoomphonecall" ];
comment = "Zoom Meetings";
};
};
};
```

## Usage

After adding web apps to your configuration:

1. Rebuild your Home Manager configuration:
```bash
home-manager switch
```

2. Your web apps will now appear in your application launcher (SUPER + SPACE)

## Adding New Apps

Simply add a new entry to the `apps` attribute set and rebuild:

```nix
programs.nix-webapps.apps.todoist = {
url = "https://todoist.com";
# icon will be auto-fetched from https://todoist.com/favicon.ico
comment = "Todoist Task Manager";
};
```

## Removing Apps

Remove the app from your configuration and rebuild. The .desktop file and icon will be automatically cleaned up.

## Notes

- Icons are **optional** - if not specified, automatically fetches from `<url>/favicon.ico`
- Icons from URLs are automatically downloaded at build time
- Local icon paths should point to PNG files
- Default launcher uses Firefox in standalone app mode
- If no custom `exec` is specified, uses the built-in webapp launcher
- MIME types are optional and only needed for protocol handlers
