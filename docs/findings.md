# 封装 OTLP exporter 过程中的问题与解决

## 背景

在把 `agent-telemetry` 从“只接收现成 exporter”进化到“内部根据 `ExporterType.Otlp(endpoint)` 自己创建 OTLP exporter”时，遇到了一个看似是别名解析失败的编译错误。

## 目标

让 `agent-telemetry` 库内部调用 `opentelemetry/otlp` 的 builder，从而应用层只需要写：

```moonbit
let exporter_type = @telemetry.Otlp(settings.otel_endpoint)
@telemetry.init_telemetry(config, exporter_type, id_generator)
```

## 现象

在 `agent-telemetry` 中 import `moonbit-community/opentelemetry/otlp` 后，`moon check` 报：

```text
Error: [4024] The type/trait @socket.Addr is not found.
Error: [4032] The type @http.Response is undefined.
Error: [4021] Value post not found in package `http`.
```

错误全部位于 `.mooncakes/moonbit-community/opentelemetry/otlp/top.mbt` 内部，而不是 `agent-telemetry` 自己的代码。

## 第一次判断：别名解析问题

`opentelemetry/otlp` 的 `moon.pkg` 中导入了 `moonbitlang/async/http` 和 `moonbitlang/async/socket`，但没有显式写 `@http` / `@socket` 别名。它依赖编译器按包路径最后一个 segment 自动生成别名。

初步怀疑是：当 `agent-telemetry` 作为本地 workspace 成员再封装 `opentelemetry/otlp` 时，这个自动别名机制失效，导致 otlp 源码里的 `@http`、`@socket` 解析失败。

## 尝试 1：把 opentelemetry 拉到本地并显式别名

为了验证，我把 `.mooncakes/moonbit-community/opentelemetry` 复制到 workspace 根目录 `./opentelemetry`，在 `moon.work` 中把它作为 workspace 成员，并把 `otlp/moon.pkg` 改成：

```text
"moonbitlang/async/http" @http,
"moonbitlang/async/socket" @socket,
```

同时把 `opentelemetry/moon.mod` 的 `async` 依赖从 `0.17.1` 升到 `0.19.2`。

**结果：错误依旧。**

这说明问题不在别名是否显式。

## 尝试 2：最小复现

新建了一个最小库包，只 import `async` 和 `opentelemetry/otlp`，同样报错。但最小包 import `async/http` 并调用 `@http.post` 时，**也报 `Value post not found`**。这说明不是 otlp 的问题，而是 `async/http` 本身的 `post` 在本地库包里不可见。

给最小测试包加上：

```text
preferred_target = "native"
```

后，`@http.post` 立刻能找到了。

## 根因

`moonbitlang/async/http` 的 `post` 和 `moonbitlang/async/socket` 的 `Addr` 都是 **native-only** 接口（由 `moon.pkg` 里的 `targets` 选项控制）。

当 `agent-telemetry/moon.mod` 没有声明 `preferred_target = "native"` 时，MoonBit 默认按非 native 后端（通常是 wasm/wasm-gc）编译依赖，导致这些 native-only 接口被过滤掉。otlp 源码再去引用 `@http.post`、`@socket.Addr` 就报“找不到”。

`moonbit-agent-observability` 应用包原本就有 `preferred_target = "native"`，所以直接 import `opentelemetry/otlp` 一直能编译通过。

## 最终修复

在 `agent-telemetry/moon.mod` 末尾加一行：

```text
preferred_target = "native"
```

然后删除本地 vendor 的 `opentelemetry/`（保留 upstream 包，不需要维护 fork）。

## 验证

```bash
cd /home/shang/repo/research-moonbit
moon check                  # ✅ 0 errors
moon test -p cybershang/agent-telemetry --target native
# Total tests: 15, passed: 15, failed: 0
```

## 结论

- 不要把这个问题归结为“子包别名 bug”或“上游包无法被库消费”。
- 当 MoonBit 报某个依赖包的类型/函数“找不到”，但该函数确实存在于源码时，优先检查 **目标后端是否匹配**。很多 `async` 子包的 API 是 native-only。
- 库的 `moon.mod` 里应显式声明 `preferred_target = "native"`，否则被应用引用时也可能因为编译上下文不同而暴露问题。

## 相关改动

- `agent-telemetry/moon.mod`：新增 `preferred_target = "native"`
- `agent-telemetry/lib.mbt`：`build_exporter` 增加 `Otlp(endpoint)` 分支
- `agent-telemetry/moon.pkg`：import `opentelemetry/otlp` 为 `@otlp`
- `moonbit-agent-observability/telemetry.mbt`：改为使用 `@telemetry.Otlp(...)`
- 后续进一步简化：直接删除 `telemetry.mbt`，在 `cmd/main/main.mbt` 里一行 `@telemetry.init_from_env(...)` 完成初始化
- `cmd/main/otel_id_generator.mbt`：内化为 `agent-telemetry/id_generator.mbt`，通过 `IdGeneratorOption.ProcessUniqueRandom` 暴露，同时支持 `SdkDefault` 和 `Custom(...)`
- README / TODO 更新：`Otlp` 与 `IdGeneratorOption` 已可用，`Custom` 退居备选
