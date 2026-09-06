# Windows Yuki Companion

Windows is intentionally scaffolded beside the existing Swift/macOS app. The first implementation target is a maintained .NET desktop client using a transparent, DPI-aware native window and Windows Graphics Capture for the configured application window.

Planned boundaries:

- `App/`: overlay, setup wizard, settings, and Windows lifecycle integration
- `Capture/`: configured-window discovery and Windows Graphics Capture
- `Bridge/`: client for the shared localhost Chrome bridge contract
- `Configuration/`: per-user settings and first-run state

The Windows client must reuse `Shared/Protocol` and `Shared/Configuration`, and must use the locked assets under `PetAssets/` without modifying the macOS target.
