// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CadenceToken} from "../src/CadenceToken.sol";

/// @dev A closed set of holders with independently tracked balances and allowances.
contract CadenceHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
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

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
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

    /// @dev Exercise revocation, dust and the finite/infinite allowance boundary frequently.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 choice) external {
        uint256[5] memory amounts = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[choice % amounts.length]);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        uint256 toIndex = (fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length;
        transfer(fromIndex, toIndex, expectedBalance[actors[fromIndex]]);
    }

    /// @dev Both legs must succeed, even after arbitrary approvals and rejected operations.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        uint256 toIndex = (fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length;
        address from = actors[fromIndex];
        address to = actors[toIndex];
        uint256 beforeFrom = expectedBalance[from];
        uint256 beforeTo = expectedBalance[to];
        uint256 amount = bound(amountSeed, 0, beforeFrom);

        transfer(fromIndex, toIndex, amount);
        assertEq(token.balanceOf(from), beforeFrom - amount, "outbound debit");
        assertEq(token.balanceOf(to), beforeTo + amount, "outbound credit");
        transfer(toIndex, fromIndex, amount);
        assertEq(token.balanceOf(from), beforeFrom, "round-trip sender balance");
        assertEq(token.balanceOf(to), beforeTo, "round-trip recipient balance");
    }

    // Expected reverts are consumed here, so fail_on_revert still detects harness failures.
    // Failed calls deliberately leave the ghost ledger unchanged. The invariant then checks
    // every holder and allowance, including accounts unrelated to the failed operation.
    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferFromOverAllowance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 approvalSeed
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approval = bound(approvalSeed, 0, type(uint256).max - 1);
        approve(fromSeed, spenderSeed, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, approval + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, to, approval + 1);
    }

    function rejectTransferFromOverBalance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        // Give sufficient approval to reach the balance check. Its attempted consumption
        // must roll back when the transfer fails, including for self-transfers.
        approve(fromSeed, spenderSeed, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroRecipient(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < allowance ? expectedBalance[from] : allowance;
        uint256 amount = bound(amountSeed, 0, available);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approve(ownerSeed, spenderSeed, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CadenceTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    CadenceToken private token;
    CadenceHandler private handler;

    function setUp() public {
        token = new CadenceToken();
        handler = new CadenceHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        // Start with four funded actors, using actual transfers to initialize the model.
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(0, i, SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = CadenceHandler.transfer.selector;
        selectors[1] = CadenceHandler.approve.selector;
        selectors[2] = CadenceHandler.transferFrom.selector;
        selectors[3] = CadenceHandler.approveBoundary.selector;
        selectors[4] = CadenceHandler.transferFullBalance.selector;
        selectors[5] = CadenceHandler.roundTrip.selector;
        selectors[6] = CadenceHandler.rejectTransferOverBalance.selector;
        selectors[7] = CadenceHandler.rejectTransferFromOverAllowance.selector;
        selectors[8] = CadenceHandler.rejectTransferFromOverBalance.selector;
        selectors[9] = CadenceHandler.rejectZeroRecipient.selector;
        selectors[10] = CadenceHandler.rejectZeroSpender.selector;
        selectors[11] = CadenceHandler.revokeAndRejectSpend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantSupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            uint256 balance = token.balanceOf(holder);
            assertEq(balance, handler.expectedBalance(holder));
            assertEq(token.allowance(holder, address(0)), 0);
            assertEq(token.allowance(address(0), holder), 0);
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
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
