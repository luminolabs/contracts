// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Core/ACL.sol";
import "../src/Core/StakeManager.sol";
import "../src/Core/JobsManager.sol";
import "../src/Core/VoteManager.sol";
import "../src/Core/BlockManager.sol";

contract DeployUpgradeableLuminoProtocol is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);

        // Deploy implementation contracts
        ACL aclImpl = new ACL();
        StakeManager stakeManagerImpl = new StakeManager();
        JobsManager jobsManagerImpl = new JobsManager();
        VoteManager voteManagerImpl = new VoteManager();
        BlockManager blockManagerImpl = new BlockManager();

        // Deploy proxies
        bytes memory emptyData = "";
        TransparentUpgradeableProxy aclProxy = new TransparentUpgradeableProxy(
            address(aclImpl),
            address(proxyAdmin),
            emptyData
        );
        TransparentUpgradeableProxy stakeManagerProxy = new TransparentUpgradeableProxy(
            address(stakeManagerImpl),
            address(proxyAdmin),
            emptyData
        );
        TransparentUpgradeableProxy jobsManagerProxy = new TransparentUpgradeableProxy(
            address(jobsManagerImpl),
            address(proxyAdmin),
            emptyData
        );
        TransparentUpgradeableProxy voteManagerProxy = new TransparentUpgradeableProxy(
            address(voteManagerImpl),
            address(proxyAdmin),
            emptyData
        );
        TransparentUpgradeableProxy blockManagerProxy = new TransparentUpgradeableProxy(
            address(blockManagerImpl),
            address(proxyAdmin),
            emptyData
        );

        // Initialize contracts through proxies
        ACL(address(aclProxy)).initialize();
        StakeManager(address(stakeManagerProxy)).initialize(/* Add necessary parameters */);
        JobsManager(address(jobsManagerProxy)).initialize(5); // Assuming 5 jobs per staker, adjust as needed
        VoteManager(address(voteManagerProxy)).initialize(address(stakeManagerProxy), address(jobsManagerProxy));
        BlockManager(address(blockManagerProxy)).initialize(address(stakeManagerProxy), address(jobsManagerProxy), address(voteManagerProxy), 1000 ether);

        // Set up roles and permissions
        bytes32 adminRole = ACL(address(aclProxy)).DEFAULT_ADMIN_ROLE();
        ACL(address(aclProxy)).grantRole(adminRole, address(stakeManagerProxy));
        ACL(address(aclProxy)).grantRole(adminRole, address(jobsManagerProxy));
        ACL(address(aclProxy)).grantRole(adminRole, address(voteManagerProxy));
        ACL(address(aclProxy)).grantRole(adminRole, address(blockManagerProxy));

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        console.log("ACL Proxy deployed at:", address(aclProxy));
        console.log("StakeManager Proxy deployed at:", address(stakeManagerProxy));
        console.log("JobsManager Proxy deployed at:", address(jobsManagerProxy));
        console.log("VoteManager Proxy deployed at:", address(voteManagerProxy));
        console.log("BlockManager Proxy deployed at:", address(blockManagerProxy));
    }
}