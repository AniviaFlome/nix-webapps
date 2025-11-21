# Webapp launcher generator
# Generates a launcher script for a specific browser and URL
{
  pkgs,
  browser,
  url,
  appName,
}:

let
  # Extract domain from URL for window class
  domain = builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] url;
  domainParts = builtins.split "/" domain;
  baseDomain = builtins.head domainParts;
  appClass = "WebApp-${builtins.replaceStrings [ "." ] [ "-" ] baseDomain}";

  # Browser categorization by engine
  isChromiumBased = builtins.elem browser [
    "brave"
    "chromium"
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

  # Generate exec command based on browser engine
  execCommand =
    if isChromiumBased then
      "${browser} --new-window --class=\"${appClass}\" --app=\"${url}\""
    else if isFirefoxBased then
      "${browser} --new-window --class \"${appClass}\" \"${url}\""
    else
      throw "Unsupported browser: ${browser}";

in
pkgs.writeShellScriptBin "webapp-launcher-${appName}" ''
  exec ${execCommand}
''
