// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LuminoToken} from "./LuminoToken.sol";
import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {IIncentiveTreasury} from "./interfaces/IIncentiveTreasury.sol";
import {LShared} from "./libraries/LShared.sol";

contract IncentiveTreasury is IIncentiveTreasury {
    IAccessManager public immutable accessManager;
    LuminoToken public immutable token;

    constructor(address _token, address _accessManager) {
        token = LuminoToken(_token);
        accessManager = IAccessManager(_accessManager);
    }

    function distributeReward(
        address recipient,
        uint256 amount,
        string calldata reason
    ) external {
        accessManager.requireRole(LShared.CONTRACTS_ROLE, msg.sender);

        if (token.balanceOf(address(this)) < amount) {
            revert InsufficientBalance(address(this), amount, token.balanceOf(address(this)));
        }

        bool success = token.transfer(recipient, amount);
        if (!success) revert TransferFailed();

        emit RewardDistributed(recipient, amount, reason);
    }

    function applyPenalty(
        address offender,
        uint256 amount,
        string calldata reason
    ) external {
        accessManager.requireRole(LShared.CONTRACTS_ROLE, msg.sender);

        if (token.balanceOf(offender) < amount) {
            revert InsufficientBalance(offender, amount, token.balanceOf(offender));
        }

        bool success = token.transferFrom(offender, address(this), amount);
        if (!success) revert TransferFailed();

        emit PenaltyApplied(offender, amount, reason);
    }

    function getBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}