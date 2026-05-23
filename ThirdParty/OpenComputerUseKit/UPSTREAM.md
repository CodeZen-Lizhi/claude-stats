Vendored from `iFurySt/open-codex-computer-use`.

- Upstream repository: https://github.com/iFurySt/open-codex-computer-use
- Upstream commit: 40b1fc4e07e46bcb7d17f8e41522304f6e3c8956
- Vendored path: `packages/OpenComputerUseKit/Sources/OpenComputerUseKit`
- License: MIT, preserved in `ThirdParty/OpenComputerUseKit/LICENSE`

This copy is vendored instead of pulled through SwiftPM or a submodule because
the upstream repository uses Git LFS assets that can break clean checkouts on
machines without `git-lfs`. Claude Stats uses this Kit as an internal app
automation runtime and does not expose the upstream MCP server as product UI.
`MCPServer.swift` is preserved in the vendor tree for provenance, but excluded
from the app's `OpenComputerUseKit` framework target.
