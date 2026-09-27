const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const BoundedFile = require("../BoundedFile.js")

function run(command) {
  return spawnSync(command[0], command.slice(1))
}

test("reads only regular files within the byte limit", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-fzf-file-"))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  const file = path.join(directory, "state.json")
  fs.writeFileSync(file, "small state\n")

  const success = run(BoundedFile.readCommand(file, 32))
  const tooLarge = run(BoundedFile.readCommand(file, 4))
  const missing = run(BoundedFile.readCommand(path.join(directory, "missing"), 32))

  assert.equal(success.status, 0)
  assert.equal(success.stdout.toString(), "small state\n")
  assert.equal(tooLarge.status, 65)
  assert.equal(tooLarge.stdout.length, 0)
  assert.equal(missing.status, 66)
})

test("atomically writes bounded private state and reports rejected writes", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-fzf-file-"))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  const file = path.join(directory, "state.json")

  const success = run(BoundedFile.writeCommand(file, "new state\n", 32))
  assert.equal(success.status, 0, success.stderr.toString())
  assert.equal(fs.readFileSync(file, "utf8"), "new state\n")
  assert.equal(fs.statSync(file).mode & 0o777, 0o600)

  const rejected = run(BoundedFile.writeCommand(file, "oversized state", 4))
  assert.equal(rejected.status, 65)
  assert.equal(fs.readFileSync(file, "utf8"), "new state\n")
})

test("atomic writes replace the state path instead of following a symlink", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-fzf-file-"))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  const external = path.join(directory, "external")
  const state = path.join(directory, "state.json")
  fs.writeFileSync(external, "untouched\n")
  fs.symlinkSync(external, state)

  const result = run(BoundedFile.writeCommand(state, "private state\n", 32))

  assert.equal(result.status, 0, result.stderr.toString())
  assert.equal(fs.readFileSync(external, "utf8"), "untouched\n")
  assert.equal(fs.lstatSync(state).isSymbolicLink(), false)
  assert.equal(fs.readFileSync(state, "utf8"), "private state\n")
})

test("prepares a private state directory but rejects a directory symlink", t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-fzf-file-"))
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  const directory = path.join(root, "state")

  const created = run(BoundedFile.prepareDirectoryCommand(directory))
  assert.equal(created.status, 0, created.stderr.toString())
  assert.equal(fs.statSync(directory).mode & 0o777, 0o700)

  fs.rmSync(directory, { recursive: true })
  const external = path.join(root, "external")
  fs.mkdirSync(external, { mode: 0o755 })
  fs.symlinkSync(external, directory)

  const rejected = run(BoundedFile.prepareDirectoryCommand(directory))
  assert.equal(rejected.status, 73)
  assert.equal(fs.statSync(external).mode & 0o777, 0o755)
  assert.equal(run(BoundedFile.writeCommand(path.join(directory, "state.json"), "state", 32)).status, 66)
})
