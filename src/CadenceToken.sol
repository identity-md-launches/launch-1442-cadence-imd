// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Cadence IMD
/// @notice A fixed supply of one billion CADENCE, with 18 decimals.
/// @dev The deploying address receives the entire supply. No further mint or burn is exposed.
contract CadenceToken is ERC20 {
    constructor() ERC20("Cadence IMD", "CADENCE") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
