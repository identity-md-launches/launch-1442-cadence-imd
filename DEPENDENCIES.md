# Vendored dependencies

All dependencies below are included as ordinary source files, with upstream
licenses. No git submodules or package-manager downloads are required to build.
Only the listed source subsets were copied; their contents are unmodified.

| Directory | Upstream release | Included files | License |
| --- | --- | --- | --- |
| `lib/openzeppelin-contracts` | [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`, and `LICENSE` | MIT |
| `lib/forge-std` | [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `src/`, `LICENSE-APACHE`, and `LICENSE-MIT` | Apache-2.0 or MIT |

Source archive SHA-256 hashes, recorded at vendoring time:

```text
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a  https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94  https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
```

`lib/SHA256SUMS` records individual vendored-file hashes. To check those files:

```sh
sha256sum -c lib/SHA256SUMS
```
