// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
suberror TestExportError

///|
async test "safe_exporter turns raised export errors into ExportFailure" {
  let inner = @sdktrace.SpanExporter::new(_batch => raise TestExportError)
  let wrapped = safe_exporter(inner)
  match wrapped.export_batch([]) {
    Ok(_) => fail("expected export failure")
    Err(err) =>
      match err {
        ExportFailure(_, msg) => assert_true(msg.contains("export failed"))
        _ => fail("expected ExportFailure")
      }
  }
}

///|
async test "init_telemetry tolerates unreachable OTLP endpoint" {
  let config = TelemetryConfig::new(service_name="test-safe-init")
  let provider = init_telemetry(config, Otlp("http://localhost:59999"))
  // Span creation and ending should not crash even though the endpoint is
  // unreachable, because the exporter is wrapped by safe_exporter.
  let tracer = @otel.tracer("test-scope")
  let span = start_span(tracer, "test.span")
  end_span_ok(span)
  match provider.force_flush() {
    Ok(_) => ()
    Err(err) =>
      match err {
        ExportFailure(_, msg) => {
          let lower = msg.to_lower()
          assert_true(
            lower.contains("connection refused") ||
            lower.contains("export failed") ||
            lower.contains("oserror"),
          )
        }
        _ => fail("expected ExportFailure")
      }
  }
}
