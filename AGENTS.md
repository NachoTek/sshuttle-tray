# sshuttle-tray

## Agent skills

### Issue tracker

Issues are tracked as GitHub issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles are used as-is (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Commands

- **Tests (both seams — engine decision core + apply validator):** `npm test` (Node built-in test runner; no dependencies to install)
- **Single test file:** `node --test tests/engine.test.cjs` / `node --test tests/apply-route-set.test.cjs`
- **QML lint:** `/usr/lib/qt6/bin/qmllint packaging/usr/share/plasma/plasmoids/io.github.nachotek.sshuttle-tray/contents/ui/*.qml` (the runtime-injected `Plasmoid` attached object is a known false positive)
- **Shell syntax:** `bash -n packaging/usr/lib/sshuttle-tray/apply-route-set.sh`
- **Unit syntax:** `systemd-analyze verify packaging/usr/lib/systemd/system/*.service` (flags the not-yet-installed helper path — expected pre-install)

There is no typecheck and no build step: the repo is the package (`packaging/` mirrors install targets exactly). The pure-JS decision core lives at `packaging/.../contents/code/engine.js` and must stay Qt-free: it is imported by both the plasmoid QML and the Node tests.
