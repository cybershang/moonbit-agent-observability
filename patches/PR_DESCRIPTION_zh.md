# 修复 `Rand::new()` 硬编码默认种子

`Rand::new()` 目前使用固定的 ChaCha8 种子，每次调用产生相同的序列。此 PR 改为从系统熵源获取种子，同时保留 `Rand::chacha8(seed~)` 用于需要确定性的场景。

## 改动

### `env/` — 跨平台熵 API `@env.rand(n)`

| 文件 | 后端 |
|---|---|
| `env/env.mbt` | 公开 API: `pub fn rand(Int) -> Bytes?` |
| `env/env_js.mbt` | JS: `crypto.getRandomValues` |
| `env/env_wasm.mbt` | WASM/WASM-GC: 返回 `None`（暂无法通过 WASI raw pointer FFI 获取熵）|
| `env/env_native.mbt` | **见下方 Windows 说明** |

### `random/` — 在 `Rand::new()` 中使用 `@env.rand`

- 优先使用 `@env.rand(32)` 获取系统熵，失败时回退到 `@env.now()` + 计数器。
- 测试改为用 `Rand::chacha8(seed=fixed_test_seed)` 指定种子。
- 新增回归测试：验证两个新 `Rand::new()` 实例的序列不同。

## Windows 构建说明

最初的 native 实现使用 `#cfg(target_os="windows")` 来区分 `rand_s` 和 `getentropy`。**MoonBit 的 `#cfg` 不支持 `target_os`**，只支持 `target`（`native`、`js` 等）。导致 POSIX 路径在所有平台都被编译，Windows 的 MSVC 链接器找不到 `getentropy`。

解决方案：在 MoonBit C 运行时（`runtime.c`）中新增统一的 FFI 函数 `moonbit_rt_get_random`，通过 C 级别的 `#ifdef _WIN32` 选择正确的 API：

```c
#ifdef _WIN32
  rand_s(...)      // Windows
#else
  getentropy(...)  // POSIX
#endif
```

补丁文件 `patches/add-moonbit_rt_get_random-to-runtime.patch` 需要 MoonBit 团队合入并在工具链发版后生效。在此之前，Windows 会回退到时间+计数器种子（仍然是非确定性的）。

## 测试结果

```
native:  6460 passed
js:      6505 passed
wasm:    6549 passed
wasm-gc: 6549 passed
```
