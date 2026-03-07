# Karatsuba BigInt WASM

This folder contains multiple bigint multiplication implementations (Karatsuba variants and schoolbook) compiled to WASM, plus small harnesses for testing and graphing.

## How to Run

### Quick benchmark graph (browser)
- From this folder start a simple HTTP server (any static server works):
	- Python: `python3 -m http.server 8000`
	- Node: `npx http-server -p 8000`
- Open http://localhost:8000/graph.html
- Wait for the status banner to reach “Done.”; the chart renders and a JPG download link appears.

### Browser test harness
- With the same HTTP server running, open http://localhost:8000/test-karatsuba.html
- Use the buttons to run correctness and performance checks in the browser.

### Node smoke test
- Run `node test-node.js` from this directory to execute a basic correctness/perf sanity pass without a browser.

Notes:
- Avoid file://; browsers block WASM fetches without HTTP.
- All WASM binaries are already built; no extra tooling is required to run the harnesses.

