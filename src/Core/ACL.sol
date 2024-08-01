// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract ACL is AccessControl, Initializable {
    //  the deployer of the network is given to the default admin
    //  role which gives other roles to contracts
    function initialize(address initialAdmin) public virtual initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
    }
}
