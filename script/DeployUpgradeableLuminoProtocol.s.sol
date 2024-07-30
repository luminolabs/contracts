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
    ProxyAdmin public proxyAdmin;
    ACL public aclImpl;
    StakeManager public stakeManagerImpl;
    JobsManager public jobsManagerImpl;
    VoteManager public voteManagerImpl;
    BlockManager public blockManagerImpl;

    TransparentUpgradeableProxy public aclProxy;
    TransparentUpgradeableProxy public stakeManagerProxy;
    TransparentUpgradeableProxy public jobsManagerProxy;
    TransparentUpgradeableProxy public voteManagerProxy;
    TransparentUpgradeableProxy public blockManagerProxy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        deployContracts(deployer);
        initializeACL(deployer);
        initializeOtherContracts(deployer);

        vm.stopBroadcast();

        logAddresses();
    }

    function deployContracts(address deployer) internal {
        proxyAdmin = new ProxyAdmin(deployer);

        aclImpl = new ACL();
        stakeManagerImpl = new StakeManager();
        jobsManagerImpl = new JobsManager();
        voteManagerImpl = new VoteManager();
        blockManagerImpl = new BlockManager();

        bytes memory emptyData = "";
        aclProxy = new TransparentUpgradeableProxy(
            address(aclImpl),
            address(proxyAdmin),
            emptyData
        );
        stakeManagerProxy = new TransparentUpgradeableProxy(
            address(stakeManagerImpl),
            address(proxyAdmin),
            emptyData
        );
        jobsManagerProxy = new TransparentUpgradeableProxy(
            address(jobsManagerImpl),
            address(proxyAdmin),
            emptyData
        );
        voteManagerProxy = new TransparentUpgradeableProxy(
            address(voteManagerImpl),
            address(proxyAdmin),
            emptyData
        );
        blockManagerProxy = new TransparentUpgradeableProxy(
            address(blockManagerImpl),
            address(proxyAdmin),
            emptyData
        );
    }

    function initializeACL(address deployer) internal {
        ACL(address(aclProxy)).initialize();
        bytes32 adminRole = ACL(address(aclProxy)).DEFAULT_ADMIN_ROLE();
        ACL(address(aclProxy)).grantRole(adminRole, deployer);
        ACL(address(aclProxy)).grantRole(adminRole, address(stakeManagerProxy));
        ACL(address(aclProxy)).grantRole(adminRole, address(jobsManagerProxy));
        ACL(address(aclProxy)).grantRole(adminRole, address(voteManagerProxy));
        ACL(address(aclProxy)).grantRole(adminRole, address(blockManagerProxy));
    }

   function initializeOtherContracts(address deployer) internal {
        require(address(stakeManagerProxy) != address(0), "StakeManager Proxy address is zero");
        require(address(jobsManagerProxy) != address(0), "JobsManager Proxy address is zero");
        require(address(voteManagerProxy) != address(0), "VoteManager Proxy address is zero");
        require(address(blockManagerProxy) != address(0), "BlockManager Proxy address is zero");

        StakeManager(address(stakeManagerProxy)).initialize(address(voteManagerProxy));
        JobsManager(address(jobsManagerProxy)).initialize(5);
        VoteManager(address(voteManagerProxy)).initialize(
            address(stakeManagerProxy),
            address(jobsManagerProxy)
        );
        BlockManager(address(blockManagerProxy)).initialize(
            address(stakeManagerProxy),
            address(jobsManagerProxy),
            address(voteManagerProxy),
            1000 ether
        );
    }

    function logAddresses() internal view {
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        console.log("ACL Proxy deployed at:", address(aclProxy));
        console.log(
            "StakeManager Proxy deployed at:",
            address(stakeManagerProxy)
        );
        console.log(
            "JobsManager Proxy deployed at:",
            address(jobsManagerProxy)
        );
        console.log(
            "VoteManager Proxy deployed at:",
            address(voteManagerProxy)
        );
        console.log(
            "BlockManager Proxy deployed at:",
            address(blockManagerProxy)
        );
    }
}
