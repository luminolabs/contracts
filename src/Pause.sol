// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin-contracts/contracts/utils/Pausable.sol";
import "./ACL.sol";
import "./Core/storage/Constants.sol";

contract Pause is Pausable, ACL, Constants {
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }
}