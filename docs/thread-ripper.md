# Bilibili-thread-ripper integration

The native Dart downloader is ported from
[lemonteaau/PiliPlus](https://github.com/lemonteaau/PiliPlus/tree/09b94559952ec2731f81e1ad7ff1410db5f17ebf)
(commit `09b94559952ec2731f81e1ad7ff1410db5f17ebf`, GPL-3.0, like PiliPlus).
The other reference implementation,
[nishuodedui1145-del/PiliPlus](https://github.com/nishuodedui1145-del/PiliPlus/tree/3988e6d081a26120ca79f1e654fe1a3422b7282f),
was also inspected; the two download engines are independent and are not mixed.
The port's upstream algorithm baseline is
[Bilibili-thread-ripper 2026.10.8.1](https://github.com/MrTangLuyao/Bilibili-thread-ripper/commit/c283962cc),
including its CDN resolver, weighted assignments and automatic concurrency.
This is a native adaptation, not the complete latest browser userscript.
The MIT notice is retained in [licenses/bilibili-thread-ripper.txt](licenses/bilibili-thread-ripper.txt)
and bundled with the application's license registry.

## Use

Settings → Audio/video settings → 线程撕裂者 (below CDN settings).
Enabled by default, with overseas nodes and automatic concurrency, matching
lemonteaau's defaults. New playback sessions use changed settings.
Automatic concurrency starts at 16 and adjusts between 8 and 64 connections.
Turn it off to select a shared audio/video limit of 4/8/16/32/64/128.
Choose mainland nodes by disabling overseas nodes. Optional custom hosts must
be Bilibili media domains; clearing them restores the regional node list.
Episode acceleration can be disabled independently.
BTR selects its own download nodes while active; manual CDN settings still
apply to direct playback when BTR is disabled.

## Native player integration

Both media_kit/mpv and Android Media3 receive media from an ephemeral HTTP
server bound only to 127.0.0.1, with random session paths. Media3 automatic
DASH quality keeps its manifest, codec selection, representation IDs and byte
indexes; only representation URLs change. Audio/video share one connection
budget. Signature paths and queries are preserved. Strict 206, Content-Range,
body-length and cross-node total-length checks reject invalid media bytes.
Failed nodes are retried, slow transfers can be hedged, and verified prefixes
can resume on another node. Output is ordered and uses socket backpressure.

mpv's newer GET for the same track cancels its previous request (seek/reopen).
Media3 may request multiple ranges per representation concurrently, so those
requests live until their sockets close. Source replacement or player disposal
closes the entire session. Startup, reload and seek buffering are excluded
from stall feedback. mpv's full-cache signal also allows startup concurrency
to settle when its configured cache cannot hold 15 seconds.

DRM and preview streams, disabled episode acceleration, live streams, local
files and non-DASH sources use direct playback. Proxy startup/registration
failure falls back to the original source; exhausted download retries produce
an HTTP error for the existing player error/retry handling. Permission checks
and signed URL refresh remain with PiliPlus. Browser MSE/UI injection and
experimental HLS live acceleration are outside this integration.

Android permits cleartext only to 127.0.0.1 for Media3, iOS enables local
networking in ATS, and sandboxed macOS builds have the server entitlement.
These declarations still require validation on the respective devices.

## Validation

```sh
flutter test test/thread_ripper_test.dart test/thread_ripper_auto_test.dart test/thread_ripper_dash_test.dart
```

The local HTTP fixtures exercise exact byte order, shared connection budgets,
HTTP/range rejection, slow-node rescue, prefix resume, disconnect/seek cleanup,
session shutdown and Media3 simultaneous ranges. JSON fixtures compare CDN
selection, weighted assignments and concurrency with the upstream algorithm.
`node tool/generate_ripper_resolver_fixture.cjs /path/to/Bilibili-thread-ripper`
regenerates them against the documented upstream baseline; algorithm changes
require review before replacing fixtures.

On hosts without GTK/X11 development packages, the normal test command may
fail in an unrelated desktop plugin's native build hook. Run the same tests
against the exact production source through a minimal Flutter dependency graph:

```sh
bash tool/test_thread_ripper.sh /path/to/flutter/bin/flutter
```

Integration validation: Flutter 3.47.7, 40 tests passed using that harness.
The standard full-app test invocation was blocked by the host's missing
GTK/X11/Xi development packages. No device playback was performed.
Automated tests do not establish battery usage or an actual speed improvement
on an overseas network.
