// Parses ~/.config/user-dirs.dirs into a list of searchable directories.
//
// The file is written by xdg-user-dirs-update and contains lines like:
//   XDG_DOWNLOAD_DIR="$HOME/Downloads"
//   XDG_DESKTOP_DIR="$HOME/"
// Entries that resolve to the home directory itself are not useful as a
// search scope (they would dwarf every other directory), so they are
// filtered out here.

function displayName(key) {
  var raw = String(key || "").toUpperCase()
  var known = {
    DESKTOP: "Desktop",
    DOWNLOAD: "Downloads",
    TEMPLATES: "Templates",
    PUBLICSHARE: "Public Share",
    DOCUMENTS: "Documents",
    MUSIC: "Music",
    PICTURES: "Pictures",
    VIDEOS: "Videos"
  }
  if (known[raw]) return known[raw]

  var words = raw.toLowerCase().split("_")
  for (var i = 0; i < words.length; i++) {
    if (words[i]) words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
  }
  return words.join(" ")
}

// Removes the surrounding double quotes and resolves the small set of
// backslash escapes the file format allows inside them (\", \\, \$, \`).
function unquote(value) {
  var v = String(value || "")
  if (v.length >= 2 && v.charAt(0) === '"' && v.charAt(v.length - 1) === '"') {
    v = v.substring(1, v.length - 1)
  }
  return v.replace(/\\(["\\$`])/g, "$1")
}

function resolvePath(rawValue, home) {
  var value = unquote(rawValue)
  if (value === "$HOME" || value.indexOf("$HOME/") === 0) {
    value = String(home) + value.slice(5)
  }
  return value
}

function isHome(path, home) {
  var p = String(path)
  var h = String(home)
  return p === h || p === h + "/"
}

// Returns [{ name, path }] for every XDG_*_DIR entry that does not point
// at the home directory itself. Order follows the file.
function parseUserDirs(raw, home) {
  var out = []
  var seenPaths = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    var match = /^XDG_([A-Za-z0-9_]+)_DIR=(.*)$/.exec(line)
    if (!match) continue
    var path = resolvePath(match[2], home)
    if (!path || path.charAt(0) !== "/" || isHome(path, home)) continue
    if (seenPaths.indexOf(path) !== -1) continue
    seenPaths.push(path)
    out.push({ name: displayName(match[1]), path: path })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    displayName: displayName,
    unquote: unquote,
    resolvePath: resolvePath,
    parseUserDirs: parseUserDirs
  }
}
