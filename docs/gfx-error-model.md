# Ape GFX Error Model

Date: 2026-04-28

This document records the v0.1 `gfx.Error_Code` contract. Human-readable messages may become more specific over time, but the code category is the stable programmatic surface.

## Public Queries

- `last_error(ctx)` returns the most recent human-readable message.
- `last_error_code(ctx)` returns the most recent `Error_Code`.
- `last_error_info(ctx)` returns both as one value.
- A fresh context starts with `Error_Code.None`.
- Error codes are set explicitly by typed helpers, not inferred from message text.

## Stable Codes

| Code | Meaning | Representative Coverage |
| --- | --- | --- |
| `None` | No error has been reported for the context yet. | `tools/test_gfx_error_codes.ps1` |
| `Validation` | The caller supplied an invalid descriptor, handle usage, pass ordering, range, or command argument. | `tools/test_gfx_error_codes.ps1` and descriptor tests |
| `Unsupported` | The request is valid API shape, but the selected backend or v0.1 feature set does not support it. | `tools/test_gfx_error_codes.ps1` |
| `Invalid_Handle` | A required handle is the zero invalid sentinel. | `tools/test_gfx_error_codes.ps1` |
| `Wrong_Context` | A live handle belongs to another `gfx.Context`. | `tools/test_gfx_error_codes.ps1` |
| `Stale_Handle` | A handle names a destroyed resource or an old generation. | `tools/test_gfx_error_codes.ps1` |
| `Backend` | The native backend returned a failure that is not classified as validation, unsupported, or device loss. | `tools/test_d3d11_error_codes.ps1` |
| `Device_Lost` | The native backend reports device removal, reset, hang, or internal driver loss. | D3D11 HRESULT mapping in `engine/gfx/backend_d3d11.odin`; deterministic runtime trigger is deferred |
| `Resource_Leak` | `shutdown` found live resources still owned by the context. | `tools/test_gfx_error_codes.ps1` |

## D3D11 Device Loss

D3D11 maps `DXGI_ERROR_DEVICE_HUNG`, `DXGI_ERROR_DEVICE_REMOVED`, `DXGI_ERROR_DEVICE_RESET`, and `DXGI_ERROR_DRIVER_INTERNAL_ERROR` to `Device_Lost`. If `GetDeviceRemovedReason` reports a failed reason, that reason also forces `Device_Lost`.

The validation suite does not currently force a real device removal because doing so is not deterministic or appropriate for a normal local test run. A future backend test seam may cover this without destabilizing the suite.
