# 13 Sink Type Taint Test Artifacts

Archived from `/tmp` on 2026-08-12.

## Contents

- `run_13_sink_current_test.sh`
  - Script used to generate the main 13 sink type test pages and logs.
- `taint_13_sink_current_20260811_184531/`
  - Main 13 sink type test run.
  - Contains generated pages, raw `*_log_*` files, stdout/stderr, profiles, and decoded logs.
- `taint_js_sink_probe_host_20260811_190339/`
  - Supplemental JavaScript sink probe.
  - `script_text` is the run that successfully produced `sinkType = javascript`.

## Useful Commands

```bash
sed -n '1,240p' taint_test_artifacts/13_sink_20260811/run_13_sink_current_test.sh
```

```bash
cat taint_test_artifacts/13_sink_20260811/taint_13_sink_current_20260811_184531/decoded/html.txt
```

```bash
cat taint_test_artifacts/13_sink_20260811/taint_js_sink_probe_host_20260811_190339/decoded/script_text.txt
```

