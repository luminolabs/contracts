// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {NodeManager} from "../src/NodeManager.sol";

contract UpgradeScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address nodeManagerProxyAddress = vm.envAddress("NODE_MANAGER_PROXY_ADDRESS");
        
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new implementation
        NodeManager newNodeManagerImpl = new NodeManager();
        
        // Upgrade the proxy to point to the new implementation (no initialization needed)
        proxyAdmin.upgradeAndCall(nodeManagerProxyAddress, address(newNodeManagerImpl), "");
        
        vm.stopBroadcast();
        
        console.log("NodeManager upgraded to implementation:", address(newNodeManagerImpl));
    }
}