"use strict"

const test = require("node:test")
const assert = require("node:assert")

const ENGINE_PATH = require("path").join(
  __dirname, "..",
  "packaging/usr/share/plasma/plasmoids/io.github.nachotek.sshuttle-tray/contents/code/engine.js"
)
const Engine = require(ENGINE_PATH)

const UNIT = "sshuttle-tray-tunnel.service"

// --- harness ---------------------------------------------------------------

function boot(opts) {
  const engine = Engine.createEngine(Object.assign({
    endpoints: [{ host: "ifconfig.me", url: "https://ifconfig.me/ip" }],
  }, opts))
  const cmds = engine.handle({ type: "init" })
  return { engine, cmds }
}

function handle(ctx, ev) {
  return ctx.engine.handle(ev)
}

// advance `seconds` of engine time in 1s clock events, collecting commands
function advance(ctx, seconds) {
  let cmds = []
  for (let i = 0; i < seconds; i++) cmds = cmds.concat(handle(ctx, { type: "clock", dt: 1 }))
  return cmds
}

function tagStartingWith(cmds, prefix) {
  return cmds.filter(c => c.tag.indexOf(prefix) === 0)
}

function echoHost(cmd) {
  return cmd.tag.slice("echo:".length)
}

// feed a result for the given planned command and return any new commands
function answer(ctx, cmd, fields) {
  return handle(ctx, Object.assign({ type: "result", tag: cmd.tag, exitCode: 0, stdout: "", stderr: "" }, fields))
}

const HOME_IP = "203.0.113.10"    // RFC 5737: this machine, direct
const OFFICE_IP = "198.51.100.20" // RFC 5737: tunnel egress

// --- slice 1: boot -----------------------------------------------------------

test("engine boots showing Off and plans the initial polls", () => {
  const ctx = boot()
  const v = ctx.engine.view()

  assert.strictEqual(v.iconState, "off")
  assert.strictEqual(v.stateWord, "Off")
  assert.strictEqual(v.causeText, "Tunnel is off")
  assert.strictEqual(v.tunnelActive, false)

  // initial polls: env files + service state, exact commands
  const tags = ctx.cmds.map(c => c.tag).sort()
  assert.deepStrictEqual(tags, ["routeset", "svc", "tunnelenv"])
  const svc = ctx.cmds.find(c => c.tag === "svc")
  assert.strictEqual(svc.command, "systemctl show -p ActiveState -p SubState " + UNIT)
  const routeset = ctx.cmds.find(c => c.tag === "routeset")
  assert.strictEqual(routeset.command, "cat /etc/sshuttle-tray/route-set.env")
  const tunnelenv = ctx.cmds.find(c => c.tag === "tunnelenv")
  assert.strictEqual(tunnelenv.command, "cat /etc/sshuttle-tray/tunnel.env")
})

// --- slice 2: start-click ----------------------------------------------------

test("start-click plans a Baseline echo round before the start command", () => {
  const ctx = boot()
  answer(ctx, ctx.cmds.find(c => c.tag === "svc"), { stdout: "ActiveState=inactive\nSubState=dead\n" })
  answer(ctx, ctx.cmds.find(c => c.tag === "routeset"), { stdout: "" , exitCode: 1 })
  answer(ctx, ctx.cmds.find(c => c.tag === "tunnelenv"), { stdout: "SSHUTTLE_REMOTE=relay.example\nSSHUTTLE_REMOTE_SHELL=ssh\n" })

  const cmds = handle(ctx, { type: "powerPressed" })
  assert.strictEqual(cmds.length, 2)
  assert.strictEqual(cmds[0].tag.indexOf("echo:"), 0)
  assert.strictEqual(cmds[0].command, "curl -4 -fsS --connect-timeout 2 --max-time 3 https://ifconfig.me/ip")
  assert.strictEqual(cmds[1].tag, "start")
  assert.strictEqual(cmds[1].command, "systemctl start " + UNIT)

  // the answer before the tunnel is up adopts that endpoint's Baseline
  const follow = answer(ctx, cmds[0], { stdout: HOME_IP + "\n" })
  assert.deepStrictEqual(follow, [])
  assert.strictEqual(ctx.engine.view().localGateway, HOME_IP)
  assert.strictEqual(ctx.engine.view().freshness, "live")
})

test("stop-click while active plans the stop command", () => {
  const ctx = boot()
  answer(ctx, ctx.cmds.find(c => c.tag === "svc"), { stdout: "ActiveState=active\nSubState=running\n" })
  const cmds = handle(ctx, { type: "powerPressed" })
  assert.deepStrictEqual(cmds.map(c => c.tag), ["stop"])
  assert.strictEqual(cmds[0].command, "systemctl stop " + UNIT)
})

// --- slice 3: activating -> verifying -> on ----------------------------------

function settleSvc(ctx, state, sub) {
  return handle(ctx, { type: "result", tag: "svc", exitCode: 0, stdout: "ActiveState=" + state + "\nSubState=" + sub + "\n" })
}

// drive one run: boot polls settle (off), popup open (Baseline adopted),
// start clicked, service reaches active
function beginRun(ctx, routeSetEnv) {
  answer(ctx, ctx.cmds.find(c => c.tag === "svc"), { stdout: "ActiveState=inactive\nSubState=dead\n" })
  answer(ctx, ctx.cmds.find(c => c.tag === "routeset"),
    routeSetEnv ? { stdout: routeSetEnv } : { stdout: "", exitCode: 1 })
  answer(ctx, ctx.cmds.find(c => c.tag === "tunnelenv"), { stdout: "SSHUTTLE_REMOTE=relay.example\n" })
  const open = handle(ctx, { type: "popupOpened" })
  answer(ctx, open.find(c => c.tag === "svc"), { stdout: "ActiveState=inactive\nSubState=dead\n" })
  if (routeSetEnv) answer(ctx, open.find(c => c.tag === "routeset"), { stdout: routeSetEnv })
  answer(ctx, open.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME_IP + "\n" })
  const press = handle(ctx, { type: "powerPressed" })
  answer(ctx, press.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME_IP + "\n" })
  answer(ctx, press.find(c => c.tag === "start"), {})
  settleSvc(ctx, "activating", "start")
  settleSvc(ctx, "active", "running")
  return ctx
}

// advance until an echo round is planned, answer it with ip (any pings that
// come due in the window are answered with success), return the window's cmds
function nextEchoAnswer(ctx, seconds, ip) {
  let cmds = advance(ctx, seconds)
  const echo = cmds.find(c => c.tag.indexOf("echo:") === 0)
  assert.ok(echo, "expected an echo round to be planned within " + seconds + "s")
  answer(ctx, echo, ip === null ? { exitCode: 28 } : { stdout: ip + "\n" })
  for (const p of cmds.filter(c => c.tag === "ping")) answer(ctx, p, { exitCode: 0 })
  return cmds.filter(c => c !== echo)
}

test("activating shows Starting, active-with-Baseline answers counts the grace, divergence turns On", () => {
  const ctx = boot()
  beginRun(ctx)

  // activating phase already passed through; we are now active and verifying
  let v = ctx.engine.view()
  assert.strictEqual(v.iconState, "starting")
  assert.strictEqual(v.stateWord, "Starting")
  assert.match(v.causeText, /^Verifying traffic… \d+s$/)

  // an answer still equal to the Baseline keeps us Verifying (not On, not Alert)
  nextEchoAnswer(ctx, 5, HOME_IP)
  v = ctx.engine.view()
  assert.strictEqual(v.iconState, "starting")

  // an answer differing from that endpoint's own Baseline -> Effective -> On
  nextEchoAnswer(ctx, 5, OFFICE_IP)
  v = ctx.engine.view()
  assert.strictEqual(v.iconState, "on")
  assert.strictEqual(v.stateWord, "On")
  assert.strictEqual(v.causeText, "Traffic routes through the Tunnel")
  assert.strictEqual(v.unverified, false)
  assert.strictEqual(v.localGateway, OFFICE_IP)
  assert.strictEqual(v.freshness, "live")
})

// --- slice 4: No-answer never moves the icon ---------------------------------

test("a No-answer round keeps the icon and shows the NO ANS chip", () => {
  const ctx = boot()
  beginRun(ctx)
  nextEchoAnswer(ctx, 5, HOME_IP)      // verifying
  nextEchoAnswer(ctx, 5, OFFICE_IP)    // On
  nextEchoAnswer(ctx, 5, null)         // every endpoint times out

  const v = ctx.engine.view()
  assert.strictEqual(v.iconState, "on", "No-answer must not move the icon")
  assert.strictEqual(v.freshness, "noans")
  assert.strictEqual(v.localGateway, OFFICE_IP, "last good value stays displayed")
})

// --- slice 5: Revert ----------------------------------------------------------

test("a Revert to Baseline holds through the grace window then Alerts", () => {
  const ctx = boot()
  beginRun(ctx)
  nextEchoAnswer(ctx, 5, HOME_IP)
  nextEchoAnswer(ctx, 5, OFFICE_IP)    // On
  nextEchoAnswer(ctx, 5, HOME_IP)      // reverted — grace window starts

  let v = ctx.engine.view()
  assert.strictEqual(v.iconState, "starting", "revert-grace renders as Starting")
  advance(ctx, 31)
  v = ctx.engine.view()
  assert.strictEqual(v.iconState, "alert")
  assert.strictEqual(v.stateWord, "Alert")
  assert.strictEqual(v.causeText, "Traffic reverted to its Baseline — Tunnel dead or bypassed")
})

// --- slice 6: never-effective (full tunnel) -----------------------------------

test("a full-tunnel start that never diverges alerts as never-effective", () => {
  const ctx = boot()
  beginRun(ctx)                          // missing route-set.env degrades to 0/0
  nextEchoAnswer(ctx, 5, HOME_IP)        // answers keep matching the Baseline

  let v = ctx.engine.view()
  assert.strictEqual(v.iconState, "starting")
  advance(ctx, 31)
  v = ctx.engine.view()
  assert.strictEqual(v.iconState, "alert")
  assert.strictEqual(v.causeText, "Tunnel never became effective")
})

// --- slice 7: scoped Route Set -> On + Unverified -----------------------------

test("a scoped Route Set without divergence or Ping Target shows On + Unverified", () => {
  const ctx = boot()
  beginRun(ctx, "SSHUTTLE_SUBNETS=192.0.2.0/24\n")
  nextEchoAnswer(ctx, 5, HOME_IP)

  advance(ctx, 31)
  const v = ctx.engine.view()
  assert.strictEqual(v.iconState, "on", "no in-scope evidence path: never an Alert")
  assert.strictEqual(v.stateWord, "On")
  assert.strictEqual(v.unverified, true)
  assert.match(v.causeText, /Unverified/)
})

// --- slice 8: Ping Target 3-strike and recovery -------------------------------

test("Ping Target 3-strike and recovery clears the Alert and proves the Tunnel", () => {
  const ctx = boot({ pingInterval: 5 })
  beginRun(ctx, "SSHUTTLE_SUBNETS=192.0.2.0/24\nSSHUTTLE_PING_TARGET=203.0.113.99\n")

  const pings = []
  for (let i = 0; i < 3; i++) {
    const cmds = advance(ctx, 5)
    const ping = cmds.find(c => c.tag === "ping")
    assert.ok(ping, "expected a ping while the Tunnel is active")
    assert.strictEqual(ping.command, "ping -4 -c1 -W2 203.0.113.99")
    answer(ctx, ping, { exitCode: 1 })
    pings.push(ping)
  }
  let v = ctx.engine.view()
  assert.strictEqual(v.iconState, "alert")
  assert.strictEqual(v.causeText, "Ping Target unreachable")

  // one success clears it; the answered ping is itself Effective-state evidence
  const cmds = advance(ctx, 5)
  answer(ctx, cmds.find(c => c.tag === "ping"), { exitCode: 0 })
  v = ctx.engine.view()
  assert.strictEqual(v.iconState, "on")
  assert.strictEqual(v.unverified, false)
})

test("a continuing Ping Target never masks a Revert (echo evidence owns the verdict)", () => {
  const ctx = boot({ pingInterval: 5 })
  beginRun(ctx, "SSHUTTLE_SUBNETS=192.0.2.0/24\nSSHUTTLE_PING_TARGET=203.0.113.99\n")

  // ping answers throughout; echo diverges (On) then reverts
  nextEchoAnswer(ctx, 5, OFFICE_IP)            // diverged -> On via echo evidence
  nextEchoAnswer(ctx, 5, HOME_IP)              // reverted to Baseline; pings still succeed

  let v = ctx.engine.view()
  assert.strictEqual(v.iconState, "starting", "revert-grace despite ping success")
  advance(ctx, 31)
  v = ctx.engine.view()
  assert.strictEqual(v.iconState, "alert", "an in-scope endpoint flipping back is a Revert")
  assert.strictEqual(v.causeText, "Traffic reverted to its Baseline — Tunnel dead or bypassed")
})


// --- slice 9: service failed ---------------------------------------------------

test("a failed service raises the Alert with the service-failed cause", () => {
  const ctx = boot()
  beginRun(ctx)
  nextEchoAnswer(ctx, 5, OFFICE_IP)      // On with live evidence
  settleSvc(ctx, "failed", "failed")

  const v = ctx.engine.view()
  assert.strictEqual(v.iconState, "alert")
  assert.strictEqual(v.causeText, "Service failed — check the journal")
})

// --- slice 11: per-endpoint evidence under a scoped Route Set -----------------

const THREE_ENDPOINTS = [
  { host: "ifconfig.me", url: "https://ifconfig.me/ip" },
  { host: "ipv4.icanhazip.com", url: "https://ipv4.icanhazip.com" },
  { host: "api.ipify.org", url: "https://api.ipify.org" },
]

test("under a scoped Route Set any single endpoint diverging from its own Baseline is On", () => {
  const ctx = boot({ endpoints: THREE_ENDPOINTS })
  answer(ctx, ctx.cmds.find(c => c.tag === "svc"), { stdout: "ActiveState=inactive\nSubState=dead\n" })
  answer(ctx, ctx.cmds.find(c => c.tag === "routeset"), { stdout: "SSHUTTLE_SUBNETS=192.0.2.0/24\n" })
  answer(ctx, ctx.cmds.find(c => c.tag === "tunnelenv"), { stdout: "SSHUTTLE_REMOTE=relay.example\n" })

  // two popup opens while off: rotation gives ifconfig.me and icanhazip Baselines
  let open = handle(ctx, { type: "popupOpened" })
  assert.strictEqual(echoHost(open.find(c => c.tag.indexOf("echo:") === 0)), "ifconfig.me")
  answer(ctx, open.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME_IP + "\n" })
  open = handle(ctx, { type: "popupClosed" }) && handle(ctx, { type: "popupOpened" })
  assert.strictEqual(echoHost(open.find(c => c.tag.indexOf("echo:") === 0)), "ipv4.icanhazip.com")
  answer(ctx, open.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME_IP + "\n" })

  // tunnel up; the power-press round gives api.ipify.org a Baseline too.
  // Rotation continues: ifconfig.me, icanhazip, then api.ipify.org
  const press = handle(ctx, { type: "powerPressed" })
  assert.strictEqual(echoHost(press.find(c => c.tag.indexOf("echo:") === 0)), "api.ipify.org")
  answer(ctx, press.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME_IP + "\n" })
  answer(ctx, press.find(c => c.tag === "start"), {})
  settleSvc(ctx, "active", "running")

  nextEchoAnswer(ctx, 5, HOME_IP)         // ifconfig.me: equal to its Baseline
  assert.strictEqual(ctx.engine.view().iconState, "starting")
  nextEchoAnswer(ctx, 5, HOME_IP)         // icanhazip: equal to its Baseline
  assert.strictEqual(ctx.engine.view().iconState, "starting", "both in-scope-blind so far")
  nextEchoAnswer(ctx, 5, OFFICE_IP)       // api.ipify.org: differs from ITS Baseline
  const v = ctx.engine.view()
  assert.strictEqual(v.iconState, "on", "one endpoint's own divergence is enough")
  assert.strictEqual(v.localGateway, OFFICE_IP)
  assert.strictEqual(v.localGatewayHost, "api.ipify.org")
})

// --- slice 10: Baseline adoption while off (roaming) --------------------------

test("popup-open while off quietly re-adopts the Baseline, so roaming never false-Alerts", () => {
  const HOME2 = "203.0.113.99"   // new network after roaming
  const ctx = boot()
  answer(ctx, ctx.cmds.find(c => c.tag === "svc"), { stdout: "ActiveState=inactive\nSubState=dead\n" })
  answer(ctx, ctx.cmds.find(c => c.tag === "routeset"), { stdout: "", exitCode: 1 })

  // first network: Baseline adopted from the popup-open round
  let open = handle(ctx, { type: "popupOpened" })
  answer(ctx, open.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME_IP + "\n" })
  handle(ctx, { type: "popupClosed" })

  // roam while the popup is closed and the Tunnel stays off
  advance(ctx, 120)

  // popup opens on the new network: the answer quietly becomes the new Baseline
  open = handle(ctx, { type: "popupOpened" })
  answer(ctx, open.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME2 + "\n" })

  // start the Tunnel; an answer equal to the NEW Baseline is Verifying, not a false On
  const press = handle(ctx, { type: "powerPressed" })
  answer(ctx, press.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME2 + "\n" })
  answer(ctx, press.find(c => c.tag === "start"), {})
  settleSvc(ctx, "active", "running")
  nextEchoAnswer(ctx, 5, HOME2)
  let v = ctx.engine.view()
  assert.strictEqual(v.iconState, "starting", "answer matches the fresh Baseline — no divergence claimed")
})

// --- slice 12: sampling budget exhaustion and hover reset ----------------------

test("echo sampling pauses at the cap (STALE) and hover re-entry resets the budget", () => {
  const ctx = boot()
  beginRun(ctx)                            // rounds 1-2 used (popup open + start click)
  nextEchoAnswer(ctx, 5, OFFICE_IP)        // round 3: On
  for (let i = 4; i <= 12; i++) nextEchoAnswer(ctx, 5, OFFICE_IP)   // rounds 4..12

  const paused = advance(ctx, 30)
  assert.strictEqual(tagStartingWith(paused, "echo:").length, 0, "no echo rounds past the cap")
  let v = ctx.engine.view()
  assert.strictEqual(v.freshness, "stale", "cap reached shows STALE")
  assert.strictEqual(v.iconState, "on", "the icon itself does not move")

  handle(ctx, { type: "hoverEnter" })
  const resumed = advance(ctx, 1)
  assert.ok(resumed.find(c => c.tag.indexOf("echo:") === 0), "hover re-entry resumes sampling")
  answer(ctx, resumed.find(c => c.tag.indexOf("echo:") === 0), { stdout: OFFICE_IP + "\n" })
  v = ctx.engine.view()
  assert.strictEqual(v.freshness, "live")
})

// --- slice 13: endpoint fallback within one tick -------------------------------

test("a failing echo endpoint falls through to the next host within the same tick", () => {
  const ctx = boot({ endpoints: THREE_ENDPOINTS })
  answer(ctx, ctx.cmds.find(c => c.tag === "svc"), { stdout: "ActiveState=inactive\nSubState=dead\n" })
  answer(ctx, ctx.cmds.find(c => c.tag === "routeset"), { stdout: "", exitCode: 1 })

  const open = handle(ctx, { type: "popupOpened" })
  const first = open.find(c => c.tag.indexOf("echo:") === 0)
  assert.strictEqual(echoHost(first), "ifconfig.me")

  // garbage body (captive portal / error page): advance immediately, no clock tick
  let follow = answer(ctx, first, { stdout: "<html>login</html>\n" })
  let next = follow.find(c => c.tag.indexOf("echo:") === 0)
  assert.strictEqual(echoHost(next), "ipv4.icanhazip.com", "fallback planned in the same tick")

  // timeout exit code: advance again
  follow = answer(ctx, next, { exitCode: 28 })
  next = follow.find(c => c.tag.indexOf("echo:") === 0)
  assert.strictEqual(echoHost(next), "api.ipify.org")

  // last host fails too: the round is a No-answer, no fourth attempt
  follow = answer(ctx, next, { exitCode: 28 })
  assert.strictEqual(tagStartingWith(follow, "echo:").length, 0)
  const v = ctx.engine.view()
  assert.strictEqual(v.freshness, "noans")
  assert.strictEqual(v.iconState, "off", "silence is never evidence")
})

// --- slice 14: cadences --------------------------------------------------------

test("popup closed: background echo and ping at ~60s while active, nothing while off", () => {
  const ctx = boot()
  beginRun(ctx, "SSHUTTLE_SUBNETS=192.0.2.0/24\nSSHUTTLE_PING_TARGET=203.0.113.99\n")
  const firstRound = nextEchoAnswer(ctx, 5, OFFICE_IP)      // On
  const firstPing = firstRound.find(c => c.tag === "ping")  // ping fires as soon as the Tunnel is active
  assert.ok(firstPing, "ping starts with the active Tunnel")
  answer(ctx, firstPing, { exitCode: 0 })
  handle(ctx, { type: "popupClosed" })

  const bg = advance(ctx, 60)
  const bgEcho = bg.find(c => c.tag.indexOf("echo:") === 0)
  assert.ok(bgEcho, "background echo at 60s while active and closed")
  answer(ctx, bgEcho, { stdout: OFFICE_IP + "\n" })
  const bgPing = bg.find(c => c.tag === "ping")
  assert.ok(bgPing, "ping continues while the popup is closed")
  answer(ctx, bgPing, { exitCode: 0 })

  // tunnel stops: sampling and pinging go quiet
  settleSvc(ctx, "inactive", "dead")
  const quiet = advance(ctx, 300)
  assert.strictEqual(tagStartingWith(quiet, "echo:").length, 0, "no echo sampling while off")
  assert.strictEqual(tagStartingWith(quiet, "ping").length, 0, "no pinging while off")

  // popup opens while off: exactly one refresh round, no cadence afterwards
  const open = handle(ctx, { type: "popupOpened" })
  assert.strictEqual(tagStartingWith(open, "echo:").length, 1, "one refresh round on open")
  assert.strictEqual(tagStartingWith(open, "ping").length, 0, "never ping while off")
  answer(ctx, open.find(c => c.tag.indexOf("echo:") === 0), { stdout: HOME_IP + "\n" })
  const still = advance(ctx, 120)
  assert.strictEqual(tagStartingWith(still, "echo:").length, 0, "no echo cadence while off")
})

// --- slice 15: Route Set apply and restart-to-apply ----------------------------

test("a Route Set change while active offers restart-to-apply; the button replans stop+start", () => {
  const ctx = boot()
  beginRun(ctx, "SSHUTTLE_SUBNETS=192.0.2.0/24\n")
  assert.strictEqual(ctx.engine.view().restartToApply, false)

  // apply unit installed a new Route Set; the Tool re-reads it on popup open
  handle(ctx, { type: "popupClosed" })
  const reopen = handle(ctx, { type: "popupOpened" })
  answer(ctx, reopen.find(c => c.tag === "routeset"), { stdout: "SSHUTTLE_SUBNETS=192.0.2.0/24 198.51.100.0/24\n" })
  let v = ctx.engine.view()
  assert.strictEqual(v.restartToApply, true, "changed Route Set + active Tunnel -> offer restart")

  const cmds = handle(ctx, { type: "restartPressed" })
  assert.deepStrictEqual(cmds.map(c => c.tag), ["stop", "start"])
  assert.strictEqual(cmds[0].command, "systemctl stop " + UNIT)
  assert.strictEqual(cmds[1].command, "systemctl start " + UNIT)
  v = ctx.engine.view()
  assert.strictEqual(v.restartToApply, false)
})

test("a Route Set change while off raises no restart offer", () => {
  const ctx = boot()
  answer(ctx, ctx.cmds.find(c => c.tag === "svc"), { stdout: "ActiveState=inactive\nSubState=dead\n" })
  answer(ctx, ctx.cmds.find(c => c.tag === "routeset"), { stdout: "", exitCode: 1 })
  const reopen = handle(ctx, { type: "popupOpened" })
  answer(ctx, reopen.find(c => c.tag === "routeset"), { stdout: "SSHUTTLE_SUBNETS=192.0.2.0/24\n" })
  assert.strictEqual(ctx.engine.view().restartToApply, false)
})

// --- slice 16: helpers, config, ping-target grace ------------------------------

test("CIDR helpers parse, reject, and contain", () => {
  assert.strictEqual(Engine.validIPv4("203.0.113.10"), true)
  assert.strictEqual(Engine.validIPv4("203.0.113.256"), false)
  assert.strictEqual(Engine.validIPv4("not-an-ip"), false)
  assert.strictEqual(Engine.validIPv4("<html>"), false)

  let p = Engine.parseSubnets("0/0")
  assert.deepStrictEqual([p.ok, p.subnets], [true, ["0/0"]])
  p = Engine.parseSubnets("192.0.2.0/24 198.51.100.7")
  assert.deepStrictEqual([p.ok, p.subnets], [true, ["192.0.2.0/24", "198.51.100.7"]])
  p = Engine.parseSubnets("192.0.2.0/24 999.1.2.3")
  assert.strictEqual(p.ok, false)
  p = Engine.parseSubnets("192.0.2.0/33")
  assert.strictEqual(p.ok, false)
  p = Engine.parseSubnets("   ")
  assert.strictEqual(p.ok, false)

  assert.strictEqual(Engine.subnetContains("192.0.2.0/24", "192.0.2.55"), true)
  assert.strictEqual(Engine.subnetContains("192.0.2.0/24", "198.51.100.55"), false)
  assert.strictEqual(Engine.subnetContains("0/0", "198.51.100.55"), true)
  assert.strictEqual(Engine.subnetsContain(["192.0.2.0/24"], "203.0.113.1"), false)
  assert.strictEqual(Engine.subnetsContain(["192.0.2.0/24"], "relay.example"), true, "hostnames cannot be judged in scope")
})

test("config event retunes the sampling cadence and cap", () => {
  const ctx = boot({ pingInterval: 1000 })
  beginRun(ctx)                            // two echo rounds used (popup open + start click)
  handle(ctx, { type: "config", config: { echoInterval: 10, sampleCap: 2 } })
  // cap of 2 already reached: sampling pauses immediately
  const paused = advance(ctx, 30)
  assert.strictEqual(tagStartingWith(paused, "echo:").length, 0, "cap honoured after reconfigure")
})

test("scoped Route Set with a Ping Target alerts never-effective once grace closes without evidence", () => {
  const ctx = boot({ pingInterval: 1000 })   // pings quiet so the grace path decides
  beginRun(ctx, "SSHUTTLE_SUBNETS=192.0.2.0/24\nSSHUTTLE_PING_TARGET=203.0.113.99\n")
  advance(ctx, 35)
  const v = ctx.engine.view()
  assert.strictEqual(v.iconState, "alert")
  assert.strictEqual(v.causeText, "Tunnel never became effective")
})










