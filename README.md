# Nix Web App Manager

A declarative Home Manager module for managing web application launchers on Linux.

## Features

- **Declarative Configuration**: Define all your web apps in your Nix configuration
- **Automatic Icon Management**: Icons are optional - automatically fetches favicons when not specified
- **Desktop Integration**: Generates `.desktop` files for app launcher integration
- **Standalone Launcher**: Built-in webapp launcher (no external dependencies)
- **Multi-Browser Support**: Automatically detects and uses available browsers
  - Supported: Zen Browser, Brave, Firefox, Chromium, Vivaldi, Microsoft Edge
  - Optional browser preference per app
- **Custom Commands**: Support for custom exec commands
- **Protocol Handlers**: MIME type support for handling custom protocols
- **Type Safe**: Uses Nix's type system for validation

## Installation

### Using Flakes (Recommended)

1. Add this flake to your Home Manager configuration:

```nix
  inputs = {
    nix-webapps.url = "github:AniviaFlome/nix-webapps";
  };
```

## Usage

### Basic Configuration

```nix
{
 imports = [ inputs.nix-webapps.homeManagerModules.default ];

 programs.nix-webapps = {
  enable = true;
  browser = "brave";  # Set your preferred browser

  apps = {
    # Icon will be automatically fetched from Gmail's favicon
    # Uses browser (brave)
    gmail = {
      url = "https://mail.google.com";
      icon = null;
      comment = "Gmail Web App";
    };

    # Or specify a custom icon URL and override browser for this app
    github = {
      url = "https://github.com";
      icon = "https://github.githubassets.com/favicons/favicon.png";
      sha = "sha256-";
      browser = "firefox";  # Override browser just for this app
      comment = "GitHub";
    };
  };
 };
}
```

### Advanced Configuration

```nix
programs.nix-webapps = {
  enable = true;
  browser = "brave";  # Global default

  apps = {
    # Without icon - automatically fetches favicon
    # Uses browser (brave)
    notion = {
      url = "https://notion.so";
      icon = null;
      comment = "Notion Workspace";
    };

    # Override browser for specific app
    slack = {
      url = "https://slack.com";
      icon = null;
      browser = "firefox";  # Will open in Firefox instead of Brave
      comment = "Slack";
    };

    # With MIME types for protocol handling
    discord = {
      url = "https://discord.com/app";
      icon = null;
      mimeTypes = [ "x-scheme-handler/discord" ];
      comment = "Discord";
    };

    # With local icon file
    custom-app = {
      url = "https://example.com";
      icon = ./icons/custom.png;
      comment = "Custom App";
    };
  };
};
```

### Apply Changes

```bash
home-manager switch
```

Your web apps will appear in your application launcher (SUPER + SPACE).

## Configuration Options

### Module Options

- **`enable`**: Enable the webapp manager module
- **`browser`**: Default browser to use for all web apps (default: `"firefox"`)
  - Supported: `"firefox"`, `"brave"`, `"chromium"`, `"zen"`, `"vivaldi"`, `"edge"`
- **`apps`**: Attribute set of web applications

### Per-App Options

- **`url`** (required): The URL of the web application
- **`icon`** (optional): Icon URL (will be downloaded) or local file path. If not specified, automatically fetches from `<url>/favicon.ico`
- **`browser`** (optional): Browser to use for this specific app. Overrides `browser`. Must be one of: `"firefox"`, `"brave"`, `"chromium"`, `"zen"`, `"vivaldi"`, `"edge"`
- **`exec`** (optional): Custom exec command. If specified, overrides both `browser` and `browser`
- **`comment`** (optional): Description shown in app launcher
- **`mimeTypes`** (optional): List of MIME types for protocol handling

## Supported Browsers

Configure your preferred browser using the `browser` option:

```nix
programs.nix-webapps.browser = "brave";
```

Supported browsers:

- `"firefox"` - Mozilla Firefox
- `"brave"` - Brave Browser
- `"chromium"` - Chromium
- `"zen"` - Zen Browser
- `"vivaldi"` - Vivaldi
- `"edge"` - Microsoft Edge

### Per-App Browser Override

You can override the browser for specific apps:

```nix
apps.slack = {
  url = "https://slack.com";
  browser = "firefox";  # Use Firefox instead of browser
};
```

## Examples

See [example-config.nix](./example-config.nix) for comprehensive examples.

## Development

### Formatting

This project uses treefmt-nix for code formatting:

```bash
nix fmt
```

### Browser Engine Categorization

The webapp launcher categorizes browsers by their rendering engine:

**Chromium-based browsers** (`--app` mode):

- Brave
- Chromium
- Vivaldi
- Microsoft Edge

**Firefox-based browsers** (standard window mode):

- Firefox
- Zen Browser

Each category uses engine-appropriate flags for optimal webapp integration.

## Compared to Bash Scripts

### Bash Script Approach

- Manual icon downloading with `curl`
- Imperative add/remove scripts
- State managed in filesystem
- Requires interactive commands to manage apps
- External dependencies for launching

### Nix Module Approach

- Automatic icon handling (or automatic favicon fetch)
- Declarative configuration
- State managed in Nix configuration
- Add/remove apps by editing config and rebuilding
- Reproducible across systems
- Type-safe configuration
- Built-in standalone launcher
- No external dependencies

## Requirements

This module requires:

- Nix with flakes enabled (recommended) or Home Manager
- At least one supported browser installed: Firefox, Brave, Chromium, Zen, Vivaldi, or Edge
- XDG directories configured

## File Locations

- Desktop files: `~/.local/share/applications/<app-name>.desktop`
- Icons: `~/.local/share/applications/icons/<app-name>.png`

## License

MIT
