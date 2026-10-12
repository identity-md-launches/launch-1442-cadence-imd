// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CadenceToken} from "../src/CadenceToken.sol";

/// @dev A closed set of holders with independently tracked balances and allowances.
contract CadenceHandler is Test {
    CadenceToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(CadenceToken token_) {
        token = token_;
        actors[0] = makeAddr("holder-0");
        actors[1] = makeAddr("holder-1");
        actors[2] = makeAddr("holder-2");
        actors[3] = makeAddr("holder-3");
        expectedBalance[actors[0]] = 1_000_000_000_000_000_000_000_000_000;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < allowance ? expectedBalance[from] : allowance;
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }
}

contract CadenceTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    CadenceToken private token;
    CadenceHandler private handler;

    function setUp() public {
        token = new CadenceToken();
        handler = new CadenceHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = CadenceHandler.transfer.selector;
        selectors[1] = CadenceHandler.approve.selector;
        selectors[2] = CadenceHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantSupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            uint256 balance = token.balanceOf(holder);
            assertEq(balance, handler.expectedBalance(holder));
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(holder, spender), handler.expectedAllowance(holder, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
