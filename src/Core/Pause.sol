// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ACL} from "./ACL.sol";
import {Shared} from "./storage/Shared.sol";
import {AccessControl} from "@openzeppelin-contracts/contracts/access/AccessControl.sol";
import {AccessControl} from "@openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin-contracts/contracts/utils/Pausable.sol";

contract Pause is Pausable, ACL, Shared {
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }
}