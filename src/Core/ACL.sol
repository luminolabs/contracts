// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../Initializable.sol";

contract ACL is AccessControl, Initializable {
    //  the deployer of the network is given to the default admin
    //  role which gives other roles to contracts
    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
