# Fix `Rand::new()` hard-coded default seed

`Rand::new()` currently uses a hard-coded ChaCha8 seed, producing the same sequence everywhere. This PR seeds it from OS entropy, while keeping `Rand::chacha8(seed~)` for deterministic use.

## Changes

### `env/` — cross-platform entropy API `@env.rand(n)`

| File | Backend |
|---|---|
| `env/env.mbt` | Public API: `pub fn rand(Int) -> Bytes?` |
| `env/env_js.mbt` | JS: `crypto.getRandomValues` |
| `env/env_wasm.mbt` | WASM/WASM-GC: returns `None` (no WASI raw pointer FFI yet) |
| `env/env_native.mbt` | **See Windows note below** |

### `random/` — use `@env.rand` in `Rand::new()`

- Prefer OS entropy via `@env.rand(32)`, fall back to `@env.now()` + counter.
- Tests updated to use explicit seeds via `Rand::chacha8(seed=fixed_test_seed)`.
- Added regression test: two fresh `Rand::new()` instances differ.

## Windows CI note

The initial native backend used MoonBit's `#cfg(target_os="windows")` to select between `rand_s` and `getentropy`. **MoonBit's `#cfg` doesn't support `target_os`** — only `target` (`native`, `js`, ...). So the POSIX path was compiled everywhere, and MSVC can't find `getentropy`.

Fix: add a single FFI function `moonbit_rt_get_random` to the MoonBit C runtime (`runtime.c`) that uses C-level `#ifdef _WIN32` to pick the right API:

```c
#ifdef _WIN32
  rand_s(...)
#else
  getentropy(...)
#endif
```

The patch (`patches/add-moonbit_rt_get_random-to-runtime.patch`) needs to be applied by the MoonBit team and shipped in a toolchain release. Until then, Windows falls back to the time+counter seed (still non-deterministic).

## Testing

```
native:  6460 passed
js:      6505 passed
wasm:    6549 passed
wasm-gc: 6549 passed
```
