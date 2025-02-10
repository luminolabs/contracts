// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Pausable} from "../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {AccessControlled} from "./AccessControlled.sol";

/**
 * @title PausableController
 * @dev Abstract contract that combines AccessControlled with pausable functionality
 */
abstract contract PausableController is AccessControlled, Pausable {
    constructor(address _accessController) AccessControlled(_accessController) {}

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
}