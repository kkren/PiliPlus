#!/usr/bin/env bash
# Run the exact production downloader/model/manifest sources without building
# unrelated desktop plugin native hooks (which need GTK/X11 development files).
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
flutter_bin=${1:-flutter}
if [[ $flutter_bin == */* ]]; then
  flutter_bin=$(realpath -- "$flutter_bin")
fi
suite_dir=$(mktemp -d "${TMPDIR:-/tmp}/piliplus-btr-suite.XXXXXX")
trap 'rm -rf -- "$suite_dir"' EXIT
cat > "$suite_dir/pubspec.yaml" <<'YAML'
name: PiliPlus
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
YAML
ln -s "$repo_dir/lib" "$suite_dir/lib"
mkdir "$suite_dir/test"
for entry in thread_ripper_test.dart thread_ripper_auto_test.dart thread_ripper_dash_test.dart fixtures; do
  ln -s "$repo_dir/test/$entry" "$suite_dir/test/$entry"
done
cd -- "$suite_dir"
"$flutter_bin" pub get --offline
"$flutter_bin" test --no-pub --reporter expanded test/thread_ripper_test.dart test/thread_ripper_auto_test.dart test/thread_ripper_dash_test.dart
