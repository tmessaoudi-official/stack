# Docker + WebAssembly (WASM)

**What it solves**: Running WebAssembly binaries directly in Docker containers without a full OS userspace. A WASM container is a single `.wasm` file — no Linux base image, no shell, no libc — resulting in images that are kilobytes instead of megabytes and start in milliseconds.

**When to reach for it**: Distributing small, portable workloads (CLI tools, serverless functions, plugins) where startup latency matters and the binary needs to run on any architecture without cross-compilation. Also useful for sandboxing untrusted code — WASM's capability model restricts filesystem and network access by default.

**The non-obvious part**: Docker WASM support (via containerd's `io.containerd.wasmtime.v1` runtime) is a separate runtime from the standard Linux container runtime. You must explicitly specify `platform: wasi/wasm` in your compose file or `--platform wasi/wasm` in `docker run`. The WASM file must be compiled for the `wasm32-wasi` target, not `wasm32-unknown-unknown` (which is for browsers). The two targets are not interchangeable.

---

References:
- Docker WASM docs: https://docs.docker.com/desktop/wasm/
- WasmEdge runtime: https://wasmedge.org/book/en/index.html
- Wasmtime runtime: https://wasmtime.dev/
