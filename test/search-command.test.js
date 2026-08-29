const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const SearchCommand = require("../SearchCommand.js")

function runSearch(query, directory, maxResults, env = process.env) {
  const command = SearchCommand.command(query, directory, maxResults)
  return spawnSync(command[0], command.slice(1), { env })
}

function resultPaths(stdout) {
  return stdout.toString("utf8").split("\0").filter(Boolean)
}

test("returns path-ranked, NUL-delimited results independently of user fzf options", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-fzf-search-"))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  fs.writeFileSync(path.join(directory, "alpha report.txt"), "")
  fs.writeFileSync(path.join(directory, "alpha\nnotes.txt"), "")
  fs.writeFileSync(path.join(directory, "beta.txt"), "")

  const env = { ...process.env, FZF_DEFAULT_OPTS: "--print-query", FZF_DEFAULT_OPTS_FILE: "/missing" }
  const result = runSearch("alpha", directory, 10, env)

  assert.equal(result.status, 0, result.stderr.toString())
  assert.deepEqual(new Set(resultPaths(result.stdout)), new Set(["alpha report.txt", "alpha\nnotes.txt"]))
})

test("limits result count", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-fzf-search-"))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  for (let index = 0; index < 5; index++) {
    fs.writeFileSync(path.join(directory, `match-${index}.txt`), "")
  }

  const result = runSearch("match", directory, 2)

  assert.equal(result.status, 0, result.stderr.toString())
  assert.equal(resultPaths(result.stdout).length, 2)
})

test("treats no matches as a successful empty result", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-fzf-search-"))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  fs.writeFileSync(path.join(directory, "alpha.txt"), "")

  const result = runSearch("does-not-match", directory, 10)

  assert.equal(result.status, 0, result.stderr.toString())
  assert.deepEqual(resultPaths(result.stdout), [])
})

test("reports an unavailable search directory", () => {
  const result = runSearch("anything", "/definitely/not/a/directory", 10)

  assert.equal(result.status, 66)
  assert.match(result.stderr.toString(), /Directory is not available/)
})
