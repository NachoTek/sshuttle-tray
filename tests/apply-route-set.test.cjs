"use strict"

const test = require("node:test")
const assert = require("node:assert")
const { execFileSync, spawnSync } = require("node:child_process")
const fs = require("node:fs")
const path = require("node:path")
const os = require("node:os")

const SCRIPT = require("path").join(__dirname, "..",
  "packaging/usr/lib/sshuttle-tray/apply-route-set.sh")

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "sshuttle-tray-apply-"))
}

// run the validator with a staged source file; returns {status, stdout, stderr, dest}
function apply(dir, content, destName) {
  const src = path.join(dir, "staged.env")
  fs.writeFileSync(src, content)
  const dest = path.join(dir, destName || "route-set.env")
  const r = spawnSync("bash", [SCRIPT, src, dest], { encoding: "utf8" })
  return { status: r.status, stdout: r.stdout, stderr: r.stderr, dest }
}

test("a valid CIDR list is accepted and installed", () => {
  const dir = tmpdir()
  const r = apply(dir, "# desired Route Set\nSSHUTTLE_SUBNETS=192.0.2.0/24  198.51.100.0/24\n")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.strictEqual(fs.readFileSync(r.dest, "utf8"), "SSHUTTLE_SUBNETS=192.0.2.0/24 198.51.100.0/24\n")
  const mode = (fs.statSync(r.dest).mode & 0o777).toString(8)
  assert.strictEqual(mode, "644")
})

test("0/0 is accepted", () => {
  const dir = tmpdir()
  const r = apply(dir, "SSHUTTLE_SUBNETS=0/0\n")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.strictEqual(fs.readFileSync(r.dest, "utf8"), "SSHUTTLE_SUBNETS=0/0\n")
})

test("garbage CIDRs are rejected and the destination is untouched", () => {
  const dir = tmpdir()
  fs.writeFileSync(path.join(dir, "route-set.env"), "SSHUTTLE_SUBNETS=0/0\n")  // sentinel
  const cases = [
    "SSHUTTLE_SUBNETS=192.0.2.0/24 999.0.2.3\n",
    "SSHUTTLE_SUBNETS=192.0.2.0/33\n",
    "SSHUTTLE_SUBNETS=not-a-cidr\n",
    "SSHUTTLE_SUBNETS=\n",
    "SOMETHING_ELSE=1\n",
  ]
  for (const c of cases) {
    const r = apply(dir, c)
    assert.notStrictEqual(r.status, 0, "expected rejection for: " + c)
    assert.strictEqual(fs.readFileSync(path.join(dir, "route-set.env"), "utf8"), "SSHUTTLE_SUBNETS=0/0\n",
      "destination must be untouched")
  }
})

test("an out-of-scope literal-IP Ping Target is accepted with a warning", () => {
  const dir = tmpdir()
  const r = apply(dir, "SSHUTTLE_SUBNETS=192.0.2.0/24\nSSHUTTLE_PING_TARGET=203.0.113.99\n")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.match(fs.readFileSync(r.dest, "utf8"), /^SSHUTTLE_PING_TARGET=203\.0\.113\.99$/m)
  assert.match(r.stdout, /outside the Route Set/)
})

test("an in-scope Ping Target and a hostname Ping Target warn nothing", () => {
  const dir = tmpdir()
  let r = apply(dir, "SSHUTTLE_SUBNETS=192.0.2.0/24\nSSHUTTLE_PING_TARGET=192.0.2.55\n")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.doesNotMatch(r.stdout, /outside the Route Set/)

  const dir2 = tmpdir()
  r = apply(dir2, "SSHUTTLE_SUBNETS=192.0.2.0/24\nSSHUTTLE_PING_TARGET=printer.example\n")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.doesNotMatch(r.stdout, /outside the Route Set/)
  assert.match(fs.readFileSync(r.dest, "utf8"), /^SSHUTTLE_PING_TARGET=printer\.example$/m)
})

test("a malformed Ping Target is rejected loudly", () => {
  const dir = tmpdir()
  const r = apply(dir, "SSHUTTLE_SUBNETS=0/0\nSSHUTTLE_PING_TARGET=bad host; rm -rf /\n")
  assert.notStrictEqual(r.status, 0)
  assert.match(r.stderr, /SSHUTTLE_PING_TARGET/)
})

test("a failed install leaves no partial file", () => {
  const dir = tmpdir()
  const src = path.join(dir, "staged.env")
  fs.writeFileSync(src, "SSHUTTLE_SUBNETS=192.0.2.0/24\n")
  const dest = path.join(dir, "no-such-dir", "route-set.env")
  const r = spawnSync("bash", [SCRIPT, src, dest], { encoding: "utf8" })
  assert.notStrictEqual(r.status, 0)
  const leftovers = fs.readdirSync(dir).filter(f => f !== "staged.env")
  assert.deepStrictEqual(leftovers, [], "no temp files may leak on failure")
})
