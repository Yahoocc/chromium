# 15 Source Type Taint Test Artifacts

Archived from `/tmp` on 2026-08-13.

## Status

Runtime verified source types: 13 / 15.

Verified:

- `cookie`
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

Not yet verified:

- `message`
- `messageOrigin`

## Contents

- `run_15_source_isolated_health_test.sh`
  - Isolated source matrix test script.
- `run_one_source_probe.sh`
  - Single-source probe script.
- `taint_15_source_isolated_health_20260813_194129/`
  - Matrix run that verified most URL/referrer/windowname source types.
- `taint_one_source_cookie_20260813_222442/`
  - Single-source run that verified `cookie`.
- `taint_one_source_storage_20260813_222443/`
  - Single-source run that verified `storage`.
- `taint_one_source_urlSearch_20260813_222444/`
  - Single-source run that verified `urlSearch`.

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

