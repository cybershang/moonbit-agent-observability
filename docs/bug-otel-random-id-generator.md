# Bug: OpenTelemetry SDK 默认 RandomIdGenerator 种子固定导致重复 Trace/Span ID

## 摘要

`moonbit-community/opentelemetry` SDK 的 `RandomIdGenerator::new()` 使用固定种子初始化随机数生成器，导致每次创建新的 `RandomIdGenerator` 实例都会产生完全相同的 ID 序列。

## 复现步骤

```moonbit
let gen1 = @sdktrace.RandomIdGenerator::new().into_id_generator()
let gen2 = @sdktrace.RandomIdGenerator::new().into_id_generator()

// gen1 和 gen2 会产生完全相同的 trace ID 序列
```

## 实际输出

```
Generator 1 trace IDs:
b773b6063d4616a51160af22a66abc3c
8c2599d9418d287c7ee07e037edc5cd6
cfaa9ee02d1c16ad0e090eef8febea79
3c82d271128b5b3e9c5addc11252a34f
df79bb617d6ceea636d553591f9d736a

Generator 2 trace IDs:
b773b6063d4616a51160af22a66abc3c
8c2599d9418d287c7ee07e037edc5cd6
cfaa9ee02d1c16ad0e090eef8febea79
3c82d271128b5b3e9c5addc11252a34f
df79bb617d6ceea636d553591f9d736a
```

## 根因分析

问题位于 `moonbit-community/opentelemetry/sdk/trace/top.mbt:672-692`：

```moonbit
pub fn RandomIdGenerator::new() -> RandomIdGenerator {
  let random = Ref(@random.Rand::new())  // <-- 问题在这里
  {
    inner: IdGenerator::new(
      () => {
        let hex = random_hex_16(random.val) + random_hex_16(random.val)
        // ...
      },
      // ...
    ),
  }
}
```

`@random.Rand::new()` 使用固定种子（ChaCha8 的默认种子），导致：
1. 每次调用 `RandomIdGenerator::new()` 都创建一个使用相同种子的随机数生成器
2. 相同种子 → 相同的随机数序列 → 相同的 trace/span ID

## 影响

- **进程重启时**：如果进程重启时 `RandomIdGenerator::new()` 被再次调用，会产生与之前相同的 ID 序列
- **多实例场景**：同一进程内创建多个 TracerProvider 时，它们的 ID 会冲突
- **测试场景**：单元测试中如果创建多个 generator，会产生相同的结果，掩盖潜在问题

## 对比其他语言实现

| 语言 | 实现方式 |
|------|---------|
| Python (opentelemetry-sdk) | 使用 `os.urandom()` 或 `random.SystemRandom()` |
| Rust (opentelemetry-rust) | 使用 `rand::rngs::OsRng` |
| Go (opentelemetry-go) | 使用 `crypto/rand` |
| **MoonBit (当前)** | 使用 `@random.Rand::new()` (固定种子) |

## 建议修复方案

### 方案 1：使用时间戳 + 进程 ID 作为种子（当前项目使用的 workaround）

```moonbit
async fn make_seed() -> Bytes {
  let (code, stdout, _stderr) = @process.collect_output("date", ["+%s%N"])
  let timestamp = if code == 0 { stdout.text().trim().to_owned() } else { "0" }
  // 混合时间戳和进程内计数器
  // ...
}
```

### 方案 2：使用系统级随机源（推荐）

如果 MoonBit 有 `crypto/rand` 或类似模块，应优先使用：

```moonbit
pub fn RandomIdGenerator::new() -> RandomIdGenerator {
  let seed = @crypto.rand_bytes(32)  // 从系统随机源获取种子
  let random = Ref(@random.Rand::chacha8(seed~))
  // ...
}
```

### 方案 3：在文档中明确说明限制

如果无法修改 SDK，至少应在文档中说明：
> `RandomIdGenerator::new()` 使用固定种子，不保证跨进程唯一性。生产环境应自定义 `IdGenerator`。

## 验证脚本

验证脚本位于 `cmd/verify_id/main.mbt`，运行方式：

```bash
moon run cmd/verify_id
```

## 相关代码

- SDK 源码：`.mooncakes/moonbit-community/opentelemetry/sdk/trace/top.mbt:672`
- 项目 workaround：`cmd/main/otel_id_generator.mbt`
- 验证脚本：`cmd/verify_id/main.mbt`
