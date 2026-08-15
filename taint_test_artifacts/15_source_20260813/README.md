# 15 Source Type Taint Test Artifacts

Archived from `/tmp` on 2026-08-13.

## Status

Runtime verified source types: 15 / 15.

Verified:

- `cookie`
- `message`
- `messageOrigin`
- `url`
- `urlHash`
- `urlProtocol`
- `urlHost`
- `urlHostname`
- `urlOrigin`
- `urlPort`
- `urlPathname`
- `urlSearch`
- `referrer`
- `windowname`
- `storage`

## Contents

- `run_15_source_isolated_health_test.sh`
  - Isolated source matrix test script.
- `run_one_source_probe.sh`
  - Single-source probe script.
- `run_message_origin_http_replay.sh`
  - Replays the real HTTP iframe/CDP `messageOrigin` test without relying on
    `--dump-dom`.
- `taint_15_source_isolated_health_20260813_194129/`
  - Matrix run that verified most URL/referrer/windowname source types.
- `taint_one_source_cookie_20260813_222442/`
  - Single-source run that verified `cookie`.
- `taint_one_source_storage_20260813_222443/`
  - Single-source run that verified `storage`.
- `taint_one_source_urlSearch_20260813_222444/`
  - Single-source run that verified `urlSearch`.
- `taint_file_message_20260814_172638/`
  - Minimal `file://` run that verified `message`.
- `taint_data_messageOrigin_20260814_221912/`
  - Minimal `data:` run that verified `messageOrigin`.
- `taint_http_messageOrigin_cdp_wait_20260815_185112/`
  - HTTP iframe/CDP run that verified `messageOrigin` with a real
    `http://127.0.0.1:<port>` origin string.

## Useful Commands

```bash
grep -o 'type = [A-Za-z0-9]*\|sinkType = [A-Za-z0-9]*' \
  taint_test_artifacts/15_source_20260813/taint_one_source_cookie_20260813_222442/decoded.txt
```

```bash
grep -o 'type = [A-Za-z0-9]*\|sinkType = [A-Za-z0-9]*' \
  taint_test_artifacts/15_source_20260813/taint_15_source_isolated_health_20260813_194129/url/decoded.txt
```

```bash
cat taint_test_artifacts/15_source_20260813/taint_one_source_storage_20260813_222443/decoded.txt
```

```bash
bash taint_test_artifacts/15_source_20260813/run_message_origin_http_replay.sh
```
