const test = require("node:test")
const assert = require("node:assert/strict")

const LastFieldState = require("../LastFieldState.js")

test("round-trips an absolute directory path", () => {
  const serialized = LastFieldState.serialize("/home/test/My Projects")

  assert.equal(serialized, '{"version":1,"path":"/home/test/My Projects"}\n')
  assert.equal(LastFieldState.parse(serialized), "/home/test/My Projects")
})

test("rejects missing, malformed, outdated, and relative state", () => {
  assert.equal(LastFieldState.parse(""), "")
  assert.equal(LastFieldState.parse("not json"), "")
  assert.equal(LastFieldState.parse('{"version":2,"path":"/tmp"}'), "")
  assert.equal(LastFieldState.parse('{"version":1,"path":"relative"}'), "")
  assert.equal(LastFieldState.serialize("relative"), "")
})

test("selects the stored directory and falls back to the first field", () => {
  const dirs = [
    { name: "Downloads", path: "/home/test/Downloads" },
    { name: "Projects", path: "/home/test/Projects" }
  ]

  assert.equal(LastFieldState.preferredIndex(dirs, "/home/test/Projects"), 1)
  assert.equal(LastFieldState.preferredIndex(dirs, "/home/test/Missing"), 0)
  assert.equal(LastFieldState.preferredIndex([], "/home/test/Projects"), -1)
})
