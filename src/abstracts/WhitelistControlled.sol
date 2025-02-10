// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IWhitelistManager} from "../interfaces/IWhitelistManager.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title WhitelistControlled
 * @dev Abstract contract providing whitelist-based access control functionality
 */
abstract contract WhitelistControlled {
    IWhitelistManager public immutable whitelistManager;

    constructor(address _whitelistManager) {
        whitelistManager = IWhitelistManager(_whitelistManager);
    }

    modifier isWhitelisted() {
        if (!whitelistManager.isWhitelisted(msg.sender)) {
            revert Errors.NotWhitelisted(msg.sender);
        }
        _;
    }
}