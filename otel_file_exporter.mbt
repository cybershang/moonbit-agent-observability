///| Internal state for the file exporter.
struct FileSpanExporterState {
  is_shutdown : Bool
}

///| A simple file-based span exporter that writes SpanData as JSON lines.
pub struct FileSpanExporter {
  path : String
  state : Ref[FileSpanExporterState]
}

///| Create a new file span exporter.
pub fn FileSpanExporter::new(path : String) -> FileSpanExporter {
  { path, state: Ref({ is_shutdown: false }) }
}

///| Export a batch of spans by appending JSON to the file.
pub async fn FileSpanExporter::export_batch(
  self : FileSpanExporter,
  batch : ArrayView[@sdktrace.SpanData],
) -> @error.OTelSdkResult {
  if self.state.val.is_shutdown {
    return @error.already_shutdown()
  }
  let sb = StringBuilder::new()
  for span in batch {
    sb.write_string(span.to_json().stringify())
    sb.write_char('\n')
  }
  // Append to file (create if not exists)
  let _ = @fs.write_file(self.path, sb.to_string().to_bytes(), append=true)
  @error.ok()
}

///| Force flush (no-op for file exporter).
pub fn FileSpanExporter::force_flush(self : FileSpanExporter) -> @error.OTelSdkResult {
  if self.state.val.is_shutdown {
    @error.already_shutdown()
  } else {
    @error.ok()
  }
}

///| Shutdown the exporter.
pub fn FileSpanExporter::shutdown(self : FileSpanExporter) -> @error.OTelSdkResult {
  if self.state.val.is_shutdown {
    @error.already_shutdown()
  } else {
    self.state.val = { is_shutdown: true }
    @error.ok()
  }
}

///| Convert into the generic SDK SpanExporter type.
pub fn FileSpanExporter::into_span_exporter(
  self : FileSpanExporter,
) -> @sdktrace.SpanExporter {
  let path = self.path
  let state = self.state
  @sdktrace.SpanExporter::new(
    async fn(batch) {
      if state.val.is_shutdown {
        return @error.already_shutdown()
      }
      let sb = StringBuilder::new()
      for span in batch {
        sb.write_string(span.to_json().stringify())
        sb.write_char('\n')
      }
      let _ = @fs.write_file(path, sb.to_string().to_bytes(), append=true)
      @error.ok()
    },
    force_flush_fn=async fn() {
      if state.val.is_shutdown {
        @error.already_shutdown()
      } else {
        @error.ok()
      }
    },
    shutdown_fn=async fn() {
      if state.val.is_shutdown {
        @error.already_shutdown()
      } else {
        state.val = { is_shutdown: true }
        @error.ok()
      }
    },
    name_fn=fn() { "file" },
  )
}
