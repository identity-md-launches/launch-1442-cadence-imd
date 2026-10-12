// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CadenceToken} from "src/CadenceToken.sol";

/// @dev Complements the original suite with boundary inputs and adversarial call sequences.
/// forge-config: default.fuzz.runs = 1000
contract CadenceTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CadenceToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new CadenceToken();
        alice = makeAddr("adversarial-alice");
        bob = makeAddr("adversarial-bob");
        spender = makeAddr("adversarial-spender");
    }

    function testDirectDeploymentMintsToSenderRatherThanOrigin() public {
        vm.prank(alice, bob);
        CadenceToken fresh = new CadenceToken();
        assertEq(fresh.name(), "Cadence IMD");
        assertEq(fresh.symbol(), "CADENCE");
        assertEq(fresh.decimals(), 18);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
        assertEq(fresh.balanceOf(address(fresh)), 0);
    }

    function testOneBaseUnitCanBeTransferredAndSpentOnlyOnce() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(bob), 1);
        _assertSupplyConserved();
    }

    function testMaximumTransferRevertsWithoutOverflowOrMutation() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        _assertSupplyConserved();
    }

    function testSelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        _assertSupplyConserved();
    }

    function testSelfDelegationRequiresAndConsumesSelfAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);

        assertTrue(token.approve(address(this), 2));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), address(this), 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), address(this), 1);
        _assertSupplyConserved();
    }

    function testAllowanceJustBelowMaximumIsFinite() public {
        uint256 approval = type(uint256).max - 1;
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approval - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approval - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        _assertSupplyConserved();
    }

    function testInfiniteApprovalCanBeRevokedAndReplacedWithFiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 2);
        _assertSupplyConserved();
    }

    function testTransactionOriginCannotBorrowAnotherSpendersAllowance() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        _assertSupplyConserved();
    }

    function testApprovalRemainsUsableAfterBalanceFailure() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);

        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        _assertSupplyConserved();
    }

    function testInfiniteApprovalDoesNotBypassBalanceCheck() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        _assertSupplyConserved();
    }

    function testZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        _assertSupplyConserved();
    }

    function testZeroDelegatedTransferToZeroRecipientStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertSupplyConserved();
    }

    function testZeroSourceCannotBeUsedToMintThroughTransferFrom() public {
        // A real, nonzero caller can supply a zero source. Even a zero-value call is
        // invalid; the allowance update validates the owner before the transfer runs.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 1);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertSupplyConserved();
    }

    function testFuzzOverdrawFromPartiallyFundedHolder(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        _assertSupplyConserved();
    }

    function testFuzzInsufficientAllowanceWithSufficientBalance(
        uint256 balanceSeed,
        uint256 approvalSeed,
        uint256 amountSeed
    ) public {
        uint256 balance = bound(balanceSeed, 1, SUPPLY);
        uint256 approval = bound(approvalSeed, 0, balance - 1);
        uint256 amount = bound(amountSeed, approval + 1, balance);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approval));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        _assertSupplyConserved();
    }

    function testFuzzInsufficientBalancePreservesEntireApproval(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        _assertSupplyConserved();
    }

    function testFuzzRejectedRecipientPreservesUsableApproval(uint256 amountSeed, uint256 approvalSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 approval = bound(approvalSeed, amount, type(uint256).max);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertSupplyConserved();

        // Prove the authorization is still usable after the rejection.
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approval == type(uint256).max ? approval : approval - amount);
        _assertSupplyConserved();
    }

    function testFuzzApprovalsAreIsolatedByBothOwnerAndSpender(
        uint256 firstApproval,
        uint256 secondApproval,
        uint256 replacement,
        uint256 amountSeed
    ) public {
        assertTrue(token.transfer(alice, SUPPLY / 2));
        assertTrue(token.transfer(bob, SUPPLY / 2));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, firstApproval));
        assertTrue(token.approve(bob, secondApproval));
        // Repeating an approval replaces it; it must neither add to it nor touch another pair.
        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        vm.prank(bob);
        assertTrue(token.approve(spender, secondApproval));
        assertEq(token.allowance(alice, spender), replacement);
        assertEq(token.balanceOf(alice), SUPPLY / 2);
        assertEq(token.balanceOf(bob), SUPPLY / 2);

        uint256 available = replacement < SUPPLY / 2 ? replacement : SUPPLY / 2;
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), amount));
        assertEq(token.allowance(alice, spender), replacement == type(uint256).max ? replacement : replacement - amount);
        assertEq(token.allowance(alice, bob), secondApproval);
        assertEq(token.allowance(bob, spender), secondApproval);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.allowance(spender, bob), 0);
        assertEq(token.balanceOf(alice), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(bob), SUPPLY / 2);
        assertEq(token.balanceOf(address(this)), amount);
        _assertSupplyConserved();
    }

    function testFuzzDelegationWithAliasedRoles(uint256 balanceSeed, uint256 amountSeed, uint8 roleSeed, bool infinite)
        public
    {
        uint256 balance = bound(balanceSeed, 1, SUPPLY);
        uint256 amount = bound(amountSeed, 0, balance);
        uint256 role = roleSeed % 4;
        // Caller is the owner, recipient, a third party on a self-transfer, or all three.
        address to = role < 2 ? bob : alice;
        address caller = role == 0 || role == 3 ? alice : (role == 1 ? bob : spender);
        uint256 approval = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(caller, approval));

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, to, amount);
        vm.prank(caller);
        assertTrue(token.transferFrom(alice, to, amount));
        assertEq(token.balanceOf(alice), to == alice ? balance : balance - amount);
        assertEq(token.balanceOf(bob), to == bob ? amount : 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, caller), infinite ? type(uint256).max : 0);
        _assertSupplyConserved();
    }

    function _assertSupplyConserved() private view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(spender),
            SUPPLY
        );
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
