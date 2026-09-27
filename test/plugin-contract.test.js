const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")

test("declares a valid on-demand Omarchy overlay entry point", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))

  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "sgruendel.fzf")
  assert.deepEqual(manifest.kinds, ["overlay"])
  assert.equal(manifest.entryPoints.overlay, "Fzf.qml")
  assert.equal(manifest.keepLoaded, undefined)
  assert.ok(fs.existsSync(path.join(root, manifest.entryPoints.overlay)))
})

test("implements the Omarchy overlay lifecycle and scoped host injection", () => {
  const qml = fs.readFileSync(path.join(root, "Fzf.qml"), "utf8")

  assert.match(qml, /^\s*property var shell: null$/m)
  assert.match(qml, /^\s*property var manifest: null$/m)
  assert.match(qml, /^\s*property bool opened: false$/m)
  assert.match(qml, /^\s*function open\(payloadJson\) \{$/m)
  assert.match(qml, /^\s*function close\(\) \{$/m)
  assert.match(qml, /root\.shell\.hide\(\(root\.manifest && root\.manifest\.id\) \|\| "sgruendel\.fzf"\)/)
})
