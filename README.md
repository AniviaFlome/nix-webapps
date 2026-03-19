# Nix Web App Manager

A nix flake that declares web applications.

## Installation

### Using Flakes (Recommended)

1. Add this flake to your Home Manager configuration:

```nix
  inputs = {
    nix-webapps.url = "github:AniviaFlome/nix-webapps";
  };
```

## Usage

### Example Configuration

```nix
{
  imports = [ inputs.nix-webapps.homeManagerModules.default ];

  programs.nix-webapps = {
    enable = true;
    browser = "brave";  # Default browser for all apps
    isolate = true;     # Isolate all apps by default (separate user-data-dir)
    extraArgs = [       # Applied to all apps (override per-app with extraArgs = [...])
      "--enable-features=UseOzonePlatform"
      "--ozone-platform-hint=auto"
    ];

    apps = {
      # Icon auto-fetched from favicon.ico
      gmail = {
        url = "https://mail.google.com";
        comment = "Gmail Web App";
      };

      # Custom icon, per-app browser override, opt out of isolation
      github = {
        url = "https://github.com";
        icon = "https://github.githubassets.com/favicons/favicon.png";
        browser = "chromium-browser";
        comment = "GitHub";
        isolate = false;  # Opt out of isolation for this app
      };
    };
  };
}
```

## Configuration Options

### Module Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | — | Enable the webapp manager module |
| `browser` | string | — | Default browser for all web apps |
| `isolate` | bool | `false` | Launch all apps with a dedicated `user-data-dir` to isolate sessions and cookies |
| `extraArgs` | list of strings | `[]` | Extra browser flags applied to all apps |

### Per-App Options

| Option | Type | Default | Description |
|---|---|---|---|
| `url` | string | — | **(Required)** URL of the web application |
| `icon` | string or null | `null` | Icon URL or local path. Auto-fetches `<url>/favicon.ico` if unset |
| `browser` | string or null | `null` | Per-app browser override |
| `exec` | string or null | `null` | Fully custom exec command (overrides browser) |
| `comment` | string | `""` | Description shown in app launcher |
| `mimeTypes` | list of strings | `[]` | MIME types for protocol handling |
| `extraArgs` | list of strings or null | `null` | Per-app browser flags. Overrides global `extraArgs` when set. `null` inherits global |
| `isolate` | bool or null | `null` | Per-app session isolation override. `null` inherits the global setting |

## Credits

Portions of this project are based on work by [Gongaku](https://github.com/Gongaku/nix-webapps), used under the MIT License.
