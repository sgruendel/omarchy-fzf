// Persistent state for the most recently focused XDG directory field.

function parse(raw) {
  var text = String(raw || "").trim()
  if (text === "") return ""

  try {
    var state = JSON.parse(text)
    if (!state || state.version !== 1 || typeof state.path !== "string") return ""
    return state.path.charAt(0) === "/" ? state.path : ""
  } catch (e) {
    return ""
  }
}

function serialize(path) {
  var value = String(path || "")
  if (value.charAt(0) !== "/") return ""
  return JSON.stringify({ version: 1, path: value }) + "\n"
}

function preferredIndex(dirs, path) {
  if (!dirs || dirs.length === 0) return -1
  for (var i = 0; i < dirs.length; i++) {
    if (dirs[i] && dirs[i].path === path) return i
  }
  return 0
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    serialize: serialize,
    preferredIndex: preferredIndex
  }
}
