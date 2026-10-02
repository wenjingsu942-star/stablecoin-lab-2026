// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {ConsentedStablecoin} from "../../src/tier3/ConsentedStablecoin.sol";
import {ConsentedVault} from "../../src/tier3/ConsentedVault.sol";

/// @title Tier 3 — burn only with the holder's consent
contract ConsentedBurnTest is Test {
    MockUSDC internal usdc;
    ConsentedStablecoin internal stable;
    ConsentedVault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant AMOUNT = 1_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        stable = new ConsentedStablecoin(admin);
        vault = new ConsentedVault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));

        usdc.faucet(alice, AMOUNT);
        vm.startPrank(alice);
        usdc.approve(address(vault), AMOUNT);
        vault.deposit(AMOUNT);
        vm.stopPrank();
    }

    function test_Deposit_StillOneToOne() public view {
        assertEq(stable.balanceOf(alice), AMOUNT);
        assertEq(stable.totalSupply(), AMOUNT);
        assertEq(vault.totalCollateral(), AMOUNT);
    }

    function test_Redeem_RevertsWithoutAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, AMOUNT
            )
        );
        vm.prank(alice);
        vault.redeem(AMOUNT);
        assertEq(stable.balanceOf(alice), AMOUNT);
    }

    function test_Redeem_WorksAfterApproval() public {
        vm.startPrank(alice);
        stable.approve(address(vault), AMOUNT);
        vault.redeem(AMOUNT);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), 0);
        assertEq(stable.totalSupply(), 0);
        assertEq(usdc.balanceOf(alice), AMOUNT);
        assertEq(vault.totalCollateral(), 0);
    }

    function test_MinterRole_CannotBurnAnothersBalance() public {
        // The old backdoor selector. This token does not implement it.
        vm.prank(address(vault));
        (bool ok,) = address(stable).call(
            abi.encodeWithSignature("burn(address,uint256)", alice, AMOUNT)
        );
        assertFalse(ok);
        assertEq(stable.balanceOf(alice), AMOUNT);

        // burn(uint256) always burns the caller. The vault holds none, so this reverts
        // and Alice's balance is untouched.
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(vault), 0, AMOUNT
            )
        );
        vm.prank(address(vault));
        stable.burn(AMOUNT);
        assertEq(stable.balanceOf(alice), AMOUNT);
    }

    function test_Attacker_CannotBurnFromAlice() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, attacker, 0, AMOUNT
            )
        );
        vm.prank(attacker);
        stable.burnFrom(alice, AMOUNT);
        assertEq(stable.balanceOf(alice), AMOUNT);
    }

    function test_Holder_CanBurnOwnCoins() public {
        vm.prank(alice);
        stable.burn(AMOUNT);
        assertEq(stable.balanceOf(alice), 0);
        assertEq(stable.totalSupply(), 0);
        // Collateral is still in the vault: burning outside redeem does not pay out.
        assertEq(vault.totalCollateral(), AMOUNT);
    }
}
