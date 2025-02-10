// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {INodeRegistryCore} from "../interfaces/INodeRegistryCore.sol";

library Nodes {
    // Custom errors
    error NotNodeOwner(address caller, uint256 nodeId);

    /**
     * @dev Ensures caller is the owner of the specified node
     * @param nodeId The ID of the node
     */
    function validateNodeOwner(INodeRegistryCore nodeRegistry, uint256 nodeId, address caller) internal view {
        if (nodeRegistry.getNodeOwner(nodeId) != caller) {
            revert NotNodeOwner(caller, nodeId);
        }
    }
}