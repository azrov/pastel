# Performance

`sh tests/perf.sh` measures what a Pastel program costs: start-up time, size, memory, requests per second and drawing speed. CI runs it on every change and fails when a number is far beyond its limit (the limits are generous: they catch mistakes, not small changes). The programs are release builds of the examples.

Measured on a small cloud machine (2 CPUs, x86_64) for 0.7:

| What | Measured | Limit |
|---|---|---|
| Console program: start and exit | 1 ms | < 100 ms |
| Desktop app: start, first frame, exit (no screen) | 27 ms | < 500 ms |
| Console program size | 388 KB | < 3 MB |
| Desktop app size (`notepad`; SDL2 and FreeType are shared libraries) | 900 KB | < 8 MB |
| Desktop app memory | 8 MB | < 80 MB |
| Web service memory, idle (`notes-api`) | 3 MB | < 40 MB |
| Requests per second (`GET /health`, a new connection for each) | 2 681 | > 1 000 |
| Failed requests under that load | 0 | 0 |
| Web service memory after the load | 3 MB | < 80 MB |
| Drawing a whole 1024×768 window with 30 controls and a 10 000-row grid | 74 frames/s | > 25 |
| Drawing one changed control (a blinking caret, a hovered button) | 1 212 frames/s | > 200 |

## What makes it fast

- **Programs are native code** compiled by Free Pascal: no runtime to start, no garbage collector.
- **Only what changed is drawn.** A control that changes asks for its own area to be painted again; the window is drawn completely only after a layout change. `PASTEL_CHECK_REPAINT=1` compares every partial repaint with a full one (the UI tests run with it); `PASTEL_FULL_REPAINT=1` turns partial repaints off.
- **Long lists draw only the visible rows** (`TListBox`, `TGrid`, `TListView`, `TTreeView`).
- **The web server** handles every connection in its own thread and keeps no per-request state beyond the request.

## What is slower than it could be

- The web server opens a new connection for every request (no keep-alive in FPC 3.2.2's server); behind nginx or Caddy this does not matter, since the proxy keeps the connections to the clients.
- Drawing is done by the CPU. A GPU backend (Skia) is planned after 1.0 for apps with heavy graphics.
