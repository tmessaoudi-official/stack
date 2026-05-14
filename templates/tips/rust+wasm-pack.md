# Rust + wasm-pack

**What it solves**: Compiling Rust code to WebAssembly (WASM) and packaging it for use in JavaScript/TypeScript projects. `wasm-pack` handles the `wasm32-unknown-unknown` target, generates JS/TS bindings via `wasm-bindgen`, and produces an npm-compatible package you can import directly.

**When to reach for it**: Performance-critical logic that needs to run in the browser (image processing, cryptography, parsing, simulation), or when you want to share a single implementation between a Rust backend and a browser frontend without rewriting in JS.

**The non-obvious part**: `wasm-pack build` produces a `pkg/` directory — not a standalone `.wasm` file. The bindings include a JS wrapper and TypeScript types, so you import it like any npm package. Build target matters: `--target web` (ES modules, no bundler), `--target bundler` (webpack/Vite), `--target nodejs` (CommonJS). Picking the wrong target produces output that silently fails to load.

Reference: https://rustwasm.github.io/wasm-pack/book/
