# Development

How to build, run and test the shell locally, and the code-quality gates CI
enforces.

## Build

```sh
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

The `Caelestia` QML plugin and native helpers are produced under `build/`.

## Run from the source tree

You can run without installing by pointing the environment at the build output:

```sh
export QML2_IMPORT_PATH="$PWD/build/qml"
export CAELESTIA_LIB_DIR="$PWD/build/lib"
qs -p shell.qml
```

Useful knobs while developing:

- `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` — point at a throwaway dir to keep your
  real config untouched while testing.
- `CAELESTIA_WALLPAPERS_DIR` — a local folder of wallpapers for the switcher.
- `CAELESTIA_UPDATE_*` — drive the updater against a local fixture (see
  [UPDATER.md](UPDATER.md#advanced-configuration)).

New files and registry changes need a full restart; hot reload is not enough for
type/registration changes.

## IPC

The shell exposes IPC handlers you can drive from the terminal:

```sh
qs ipc --pid <PID> call nexus openPage "2"     # open a Nexus page by index
qs ipc --pid <PID> call updates check          # trigger an update check
qs ipc --pid <PID> call updates status         # read updater state as JSON
```

## Code-quality gates

CI runs three QML gates; **all must produce zero output / zero violations**. Run
them locally before pushing.

### 1. Formatting (`qmlformat`)

A file is formatted iff `qmlformat` reproduces it byte-for-byte:

```sh
for f in $(git ls-files '*.qml'); do
  qmlformat "$f" | diff -u "$f" - >/dev/null || echo "FORMAT: $f"
done
```

Fix in place with `qmlformat -i <file>`.

### 2. Section conventions

`scripts/qml-lint-conventions.py` enforces the upstream declaration order:

```
id → property declarations → signals → functions → bindings → child objects
```

with a blank line between sections. Run:

```sh
python3 scripts/qml-lint-conventions.py
```

The `--fix` flag only inserts missing separators; reordering is manual. Two
upstream idioms the checker expects: inside `Connections { }` put the
`function onX…` handlers **before** `target:`; keep `pragma ComponentBehavior:
Bound` at the very top of component files.

### 3. Linting (`qmllint`)

`qmllint` fails on **any** warning. It resolves `qs.*` types from a Quickshell-
generated tooling directory referenced by `.qmlls.ini`, so you must (re)generate
it after adding or renaming QML files/singletons:

```sh
touch .qmlls.ini
QT_QPA_PLATFORM=offscreen QML2_IMPORT_PATH="$PWD/build/qml:$QML2_IMPORT_PATH" \
  timeout 2 qs -p .

build_dir=$(grep -oP '(?<=buildDir=")[^"]+' .qmlls.ini)
imports=$(grep -oP '(?<=importPaths=")[^"]+' .qmlls.ini | tr ':' '\n')
args=(-I "$build_dir"); for p in $imports; do args+=(-I "$p"); done
qmllint --import disable "${args[@]}" $(git ls-files '*.qml')
```

Common suppressions, used upstream and safe to reuse:

- `// qmllint disable missing-property` — runtime-only members the compiler
  can't see (e.g. `Process.exitCode`, delegate `modelData` on `MenuItem`).
- `// qmllint disable signal-handler-parameters` — for `onExited: code => …`.
- `// qmllint disable incompatible-type` — for `Process.environment` map
  literals.

Prefer qualifying an access with its `id` (e.g. `seedSwatch.modelData`) over
suppressing, when a real id exists.

## Testing the updater

The updater helper has a self-contained fixture test (no network, no changes to
your system):

```sh
bash tests/updater/run-fixture.sh
```

It covers the happy path plus the failure modes: tampered digest (must abort)
and rollback without a backup (must fail cleanly).

## C++

`plugin/` builds against Qt 6. CI checks it with `clang-format`, `clang-tidy`
and `clazy`:

```sh
cmake -B build -G Ninja -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
run-clang-tidy -p build -quiet -warnings-as-errors='*' -source-filter='^(?!.*/build/).*\.cpp$'
```
