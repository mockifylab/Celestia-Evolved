# The safe in-app updater

Celestia Shell Reimagined can update itself from **Nexus → Updates**, with no
terminal required. The updater is deliberately conservative: it will never put
the shell into a half-updated or unbootable state, and every change can be
undone.

## How to use it

1. Open **Nexus** and go to the **Updates** page.
2. Press **Check**. The shell queries the release feed and compares versions.
3. If an update is available, press **Update**. The download → verify → stage →
   apply sequence runs automatically; the status card shows each step.
4. Restart the shell to load the new version.
5. If anything is wrong, press **Roll back** to restore the previous version,
   then restart again.

The same flow is scriptable over IPC (useful for headless setups):

```sh
qs ipc -c caelestia call updates check
qs ipc -c caelestia call updates status      # JSON: state, current, latest, ...
qs ipc -c caelestia call updates download
qs ipc -c caelestia call updates rollback
```

## Safety model

The updater follows a strict **download → verify → stage → activate** pipeline,
and it refuses to skip steps:

- **Checksum-gated.** The release feed must advertise a SHA-256 digest for the
  asset. If it does not, the updater **refuses to apply** the update rather than
  installing something it cannot verify. A verification failure aborts before
  anything touches the install directory.
- **Staged first.** The archive is extracted to a staging area under the cache
  and only rsynced into place after it verifies clean.
- **Backup before apply.** The current install is copied to a backup before
  activation. If activation fails midway, the helper automatically restores the
  backup, so the shell is never left broken.
- **User data preserved.** Your `user.conf` / `user.conf.d`, cache and any
  installed `plugins/` are excluded from the sync, so local customisations and
  plugins survive updates (they are also protected from the mirror's deletions).
- **One-click rollback.** `Roll back` swaps the backup back into place. The same
  protected paths are kept during a rollback.

All destructive steps live in a single, auditable shell helper
(`assets/update/apply_update.sh`); the QML service only orchestrates it and
maintains the UI state machine. This keeps the risky logic small and testable.

### State machine

| State | Meaning |
| --- | --- |
| `idle` | Nothing checked yet |
| `checking` | Querying the release feed |
| `upToDate` | Installed version is the latest |
| `available` | A newer release was found |
| `downloading` → `verifying` → `staging` → `applying` | The activation pipeline |
| `applied` | Update installed; restart to load it |
| `rollingBack` | Restoring the previous version |
| `error` | A step failed; the install directory was left untouched or restored |

## How the installed version is known

A source-only update cannot change the version that is compiled into the C++
plugin, so the **install directory itself** is the authoritative record. After a
successful activation the helper writes the new version into `<install>/VERSION`,
and `Updater.currentVersion` resolves the installed version in this order:

1. `CAELESTIA_UPDATE_CURRENT` (explicit override, for testing / self-hosting),
2. the version applied in the current session (before a shell restart),
3. `<install>/VERSION` — written by the updater, and shipped inside every
   release tarball since v1.0.2,
4. the version compiled into the plugin — the fallback for older installs that
   pre-date `VERSION` (they report the version they were built from until their
   first successful in-app update).

The Updates page, the About page and the "is this release newer?" comparison all
read the same value, so a successfully installed release is never offered again
after a restart.

## Where things live

| Path | Purpose |
| --- | --- |
| `$XDG_CACHE_HOME/caelestia/updates/` | Update working directory |
| `…/updates/download.bin` | The downloaded archive |
| `…/updates/staged/` | Extracted payload awaiting activation |
| `…/updates/meta/backup/` | Known-good copy of the previous install |
| `…/updates/meta/rollback.env` | Rollback metadata |
| `<install>/VERSION` | Authoritative installed version (written on apply) |

Clearing the `updates/` cache directory removes all updater state (including the
rollback backup).

## Advanced configuration

Every aspect of the updater is overridable through environment variables, which
makes it possible to test the full flow offline or point the shell at your own
release server:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CAELESTIA_UPDATE_REPO` | `mockifylab/Celestia-Shell_Reimagend` | GitHub `owner/repo` used to build the default feed URL |
| `CAELESTIA_UPDATE_FEED` | GitHub Releases `latest` API URL | Release feed (any URL, incl. `file://`) |
| `CAELESTIA_UPDATE_CURRENT` | installed `VERSION` file, else compiled-in version | Override the "installed" version for comparison |
| `CAELESTIA_UPDATE_TARGET` | the running shell's install dir | Directory that gets updated / rolled back |
| `CAELESTIA_UPDATE_HELPER` | installed `assets/update/apply_update.sh` | Path to the helper script |
| `CAELESTIA_UPDATE_AUTOCHECK` | unset | Set to `1` to check automatically on startup |

### The release feed

The feed is any endpoint that returns GitHub Releases JSON shape:

```json
{
  "tag_name": "v1.0.1",
  "body": "## What's changed\n- ...",
  "assets": [
    {
      "name": "caelestia-shell-1.0.1.tar.gz",
      "browser_download_url": "https://.../caelestia-shell-1.0.1.tar.gz",
      "digest": "sha256:<64 hex chars>"
    }
  ]
}
```

The updater picks a `tar.gz`/`tgz`/`tar.xz`/`zip` asset, reads its `digest`, and
compares `tag_name` against the installed version using semver ordering
(`major.minor.patch` with optional `-prerelease`). A release outranks any
pre-release of the same version.

### Self-hosting

Serve the JSON above (plus the archive) from anywhere and point the shell at it:

```sh
export CAELESTIA_UPDATE_FEED=https://updates.example.com/caelestia/latest.json
```

Because the feed is a plain URL and downloads go through `curl`/`wget`, you can
host releases on any static file server — you do not need GitHub.

## Testing the updater

The helper script is covered by a self-contained fixture test that exercises the
whole pipeline against a local `file://` fixture — including the failure paths
(tampered digest, rollback without a backup):

```sh
bash tests/updater/run-fixture.sh
```

It builds a throwaway install directory, a payload tarball and a GitHub-style
feed under `/tmp`, then asserts on every stage. Nothing on your real system is
touched.
