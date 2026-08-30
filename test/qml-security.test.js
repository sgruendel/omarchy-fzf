const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

test("renders every Text item as plain text", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Fzf.qml"), "utf8")
  const lines = qml.split("\n")
  const textItems = []

  for (let start = 0; start < lines.length; start++) {
    const match = lines[start].match(/^(\s*)Text \{$/)
    if (!match) continue

    const closingBrace = `${match[1]}}`
    const end = lines.findIndex((line, index) => index > start && line === closingBrace)
    assert.notEqual(end, -1, `unclosed Text item at line ${start + 1}`)
    textItems.push(lines.slice(start, end + 1).join("\n"))
  }

  assert.ok(textItems.length > 0, "expected at least one Text item")
  for (const item of textItems) {
    assert.match(item, /^\s*textFormat: Text\.PlainText$/m)
  }
})
