#!/usr/bin/env bash
# Run production roaming sources without unrelated GTK/X11 native plugin hooks.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
flutter_bin=${1:-flutter}
if [[ $flutter_bin == */* ]]; then
  flutter_bin=$(realpath -- "$flutter_bin")
fi
suite_dir=$(mktemp -d "${TMPDIR:-/tmp}/piliplus-roaming-suite.XXXXXX")
trap 'rm -rf -- "$suite_dir"' EXIT
python3 - "$repo_dir" "$suite_dir" <<'PY'
import json
import pathlib
import sys
import urllib.parse
repo, suite = map(pathlib.Path, sys.argv[1:])
packages = json.loads((repo / '.dart_tool/package_config.json').read_text())['packages']
dio = next(p for p in packages if p['name'] == 'dio')
cache = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(dio['rootUri']).path)).parents[2]
(suite / '.pub-cache').mkdir()
(suite / '.pub-cache/hosted').symlink_to(cache / 'hosted', target_is_directory=True)
deps = {'flutter': {'sdk': 'flutter'}, 'material_ui': 'any', 'dio': 'any', 'crypto': 'any', 'hive_ce': 'any', 'easy_debounce': 'any'}
for name in ('flutter_smart_dialog', 'get'):
    entry = next(p for p in packages if p['name'] == name)
    uri = urllib.parse.urljoin((repo / '.dart_tool/package_config.json').as_uri(), entry['rootUri'])
    deps[name] = {'path': urllib.parse.unquote(urllib.parse.urlparse(uri).path)}
(suite / 'pubspec.yaml').write_text(json.dumps({
    'name': 'PiliPlus', 'publish_to': 'none',
    'environment': {'sdk': '>=3.13.0 <4.0.0'}, 'dependencies': deps,
    'dev_dependencies': {'flutter_test': {'sdk': 'flutter'}},
}))
PY
ln -s "$repo_dir/lib" "$suite_dir/lib"
mkdir "$suite_dir/test"
ln -s "$repo_dir/test/http" "$suite_dir/test/http"
ln -s "$repo_dir/test/bili_roaming_dialog_test.dart" "$suite_dir/test/bili_roaming_dialog_test.dart"
cd -- "$suite_dir"
export PUB_CACHE="$suite_dir/.pub-cache"
"$flutter_bin" pub get --offline
"$flutter_bin" test --no-pub --reporter expanded test/http/bili_roaming_test.dart test/bili_roaming_dialog_test.dart
