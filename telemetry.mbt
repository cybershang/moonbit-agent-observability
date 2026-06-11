// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
/// Initialize OpenTelemetry tracer provider from application settings.
///
/// - Uses the print exporter when `settings.otel_stdout` is `true`.
/// - Otherwise builds an OTLP/HTTP exporter pointing at `settings.otel_endpoint`
///   and attaches it to a batch span processor.
/// - Falls back to a no-op provider if the OTLP exporter cannot be built.
/// - Sets the built provider as the global tracer provider.
///
/// Returns the provider so the caller can `force_flush()` and `shutdown()`.
pub async fn init_telemetry(
  settings : Settings,
  id_generator : @sdktrace.IdGenerator,
) -> @sdktrace.SdkTracerProvider {
  // Build the OTel resource.
  // Default detectors pick up OTEL_SERVICE_NAME / OTEL_RESOURCE_ATTRIBUTES.
  // If no service.name is provided, fall back to "agent-observability".
  let resource = {
    let base = @resource.Resource::builder().build()
    match @env.get_env_var("OTEL_SERVICE_NAME") {
      Some(_) => base
      None =>
        base.merge(
          @resource.Resource::new([
            @common.KeyValue::new("service.name", String("agent-observability")),
          ]),
        )
    }
  }

  // Configure a REPL-friendly batch processor:
  // small batches, short scheduled delay, so spans show up in Jaeger quickly.
  let batch_config = @sdktrace.BatchConfig::new(
    max_queue_size=64,
    max_export_batch_size=16,
    scheduled_delay_millis=1000,
    export_timeout_millis=5000,
  )

  // Initialize OpenTelemetry SDK
  // OTEL_STDOUT=true uses the print exporter; otherwise use OTLP/HTTP.
  let provider = if settings.otel_stdout {
    let exporter = @print.SpanExporter::new()
    @sdk.tracer_provider_builder()
    .with_resource(resource)
    .with_id_generator(id_generator)
    .with_simple_exporter(exporter.into_span_exporter())
    .build()
  } else {
    match @otlp.SpanExporter::builder()
      .with_http()
      .with_endpoint(settings.otel_endpoint)
      .build() {
      Ok(exporter) =>
        @sdk.tracer_provider_builder()
        .with_resource(resource)
        .with_id_generator(id_generator)
        .with_batch_exporter(exporter.into_span_exporter(), config=batch_config)
        .build()
      Err(err) => {
        let err_text = match err {
          InvalidConfig(key, msg) => "InvalidConfig(\{key}, \{msg})"
          UnsupportedProtocol(p) => "UnsupportedProtocol(\{p})"
          UnsupportedCompressionAlgorithm(a) =>
            "UnsupportedCompressionAlgorithm(\{a})"
        }
        @stdio.stdout.write("Failed to build OTLP exporter: " + err_text + "\n")
        @sdk.tracer_provider_builder()
        .with_resource(resource)
        .with_id_generator(id_generator)
        .build()
      }
    }
  }
  @sdk.set_tracer_provider(provider)
  provider
}
