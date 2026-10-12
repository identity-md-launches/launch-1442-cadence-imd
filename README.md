# Cadence IMD (CADENCE)

A fixed-supply ERC-20 implemented in `src/CadenceToken.sol`, using the vendored
OpenZeppelin Contracts v5.0.2 ERC-20 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `CadenceToken` |
| Token name | `Cadence IMD` |
| Symbol | `CADENCE` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None; ABI argument list `[]` |
| Constructor transaction value | `0` |
| Initial recipient | The deploying address (`msg.sender`) |
| Launch chain | Ethereum, chain ID `1` |

## Build and check

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer enabled
with 200 runs, and `bytecode_hash = "none"`. Solidity dependencies and their
licenses are ordinary files under `lib/`; no package installation, submodule,
RPC, environment variables, FFI, or filesystem permission is needed by the
tests. With the pinned compiler present, builds and tests work without network
access. Dependency versions and provenance are in `DEPENDENCIES.md`.

The unit tests cover metadata, the mint event, CREATE2 factory deployment,
exact launch distributions and claims, transfers, self-transfers, zero amounts,
finite and infinite approvals, revocation, delegated transfers, invalid
recipients, insufficient funds or allowance, failure rollback, and rejection
of administrative calls. Three fuzz tests run 512 cases each. A stateful
invariant test runs 128 sequences of 64 operations against an independent
balance and allowance model. Tests create fresh state and do not share an
environment or depend on execution order.

## Behavior and assumptions

The constructor makes one mint of the entire supply to `msg.sender`. Deploying
through a factory gives that factory all tokens, regardless of the transaction
origin or the caller of the factory. A direct deployment gives all tokens to
the deploying account. The constructor takes no addresses and calls no other
contracts. There are no post-deployment initialization steps.

The token uses ordinary ERC-20 transfers with no taxes, transfer hooks, rebases,
limits, special exemptions, or external calls. Every successful transfer moves
the exact requested amount and returns `true`. Zero-value transfers to valid
addresses succeed and emit `Transfer`. Invalid operations revert with the
vendored ERC-20's custom errors; all state changes in a failed call roll back.

`approve` replaces the caller's allowance and emits `Approval`. `transferFrom`
requires allowance even when the caller is the holder or deployer. Finite
allowances decrease when spent. An allowance of `type(uint256).max` stays
unchanged until replaced or revoked. This OpenZeppelin implementation does not
emit `Approval` when `transferFrom` spends allowance; integrations should query
`allowance` for its current value. Holders should approve only the amount they
intend to expose to a spender. When replacing an existing allowance, first
revoke it and confirm the revocation to avoid the standard ERC-20 allowance
replacement race.

The supply cannot grow or shrink after construction. The contract exposes no
mint, burn, owner, pause, blacklist, seizure, upgrade, or rescue functions.
Transferring to the zero address and approving the zero spender revert.
Ordinary native ETH transfers revert. Tokens sent to the token contract itself,
or to another address without a usable withdrawal mechanism, cannot be recovered
by an administrator. Forced ETH has no withdrawal path either.

## Deployment and operational responsibilities

Deploy the creation bytecode for `src/CadenceToken.sol:CadenceToken` with no
appended constructor arguments and no ETH. Its artifact is
`out/CadenceToken.sol/CadenceToken.json`. There are no library link placeholders,
external contract prerequisites, keys, owner addresses, or configurable settings.
The launch system is responsible for deploying from the reviewed build and
recording the actual deployment address. This repository does not broadcast
transactions or supply a launch manifest.

For the specified custom-token launch, the factory receives 100% of the supply.
The launch infrastructure then distributes the 10% swarm share, seeds the pool
with 80%, and forwards the remaining 10% according to the task's launch terms.
These actions and AMM settings belong to the external launch system. The token
does not allocate supply to any other contract in its constructor. The local
factory test verifies exact token movement for distribution, claims, and both
pool transfer directions; it is not a Uniswap v4 integration test.

After deployment the launch operator should verify the source with these build
settings, confirm metadata and total supply, and check the constructor's single
mint event and subsequent distribution events. No token administrator or ongoing
keeper is required. Holders control their balances and approvals; the deployer
has no authority over other holders. The separate launch admission system runs
the supplied protected integration checks against its actual manifest and pool
setup.

The code was reviewed locally against the supplied security reference. The
small constructor-only extension adds no external calls, pricing logic,
signature handling, or privileged operations. Foundry build, unit/fuzz tests,
stateful invariants, and formatting are the local validation tools. Slither and
Mythril were not run. This work is not an independent security audit; independent
review and production deployment verification remain release responsibilities.
