// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ConsentedStablecoin} from "./ConsentedStablecoin.sol";

/// @title 1:1 vault that cannot burn a balance the holder did not approve
/// @notice `deposit` still mints, so this contract needs MINTER_ROLE.
///         `redeem` calls `burnFrom`, which spends the holder's allowance.
///         Holding MINTER_ROLE no longer lets the vault erase an arbitrary wallet.
contract ConsentedVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateral;
    ConsentedStablecoin public immutable stable;

    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientCollateral();

    constructor(IERC20 collateral_, ConsentedStablecoin stable_) {
        if (address(collateral_) == address(0) || address(stable_) == address(0)) {
            revert ZeroAddress();
        }
        collateral = collateral_;
        stable = stable_;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        stable.mint(msg.sender, amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Burn the caller's stablecoin and return the same amount of collateral.
    /// @dev The caller must `approve` this vault first. No approval, no burn.
    function redeem(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > collateral.balanceOf(address(this))) revert InsufficientCollateral();
        stable.burnFrom(msg.sender, amount);
        collateral.safeTransfer(msg.sender, amount);
        emit Redeemed(msg.sender, amount);
    }

    function totalCollateral() external view returns (uint256) {
        return collateral.balanceOf(address(this));
    }
}
