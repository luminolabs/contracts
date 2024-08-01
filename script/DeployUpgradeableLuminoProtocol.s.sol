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

/// @title DeployUpgradeableLuminoProtocol
/// @notice This contract is responsible for deploying and initializing the Lumino Protocol's core contracts
/// @dev This script uses the TransparentUpgradeableProxy pattern for upgradeable contracts
contract DeployUpgradeableLuminoProtocol is Script {
    /// @notice The private key of the deployer account
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    
    /// @notice The address of the deployer account
    address deployer = vm.addr(deployerPrivateKey);
    
    /// @notice The ProxyAdmin contract instance
    ProxyAdmin public proxyAdmin;
    
    /// @notice The implementation contract instances
    ACL public aclImpl;
    StakeManager public stakeManagerImpl;
    JobsManager public jobsManagerImpl;
    VoteManager public voteManagerImpl;
    BlockManager public blockManagerImpl;

    /// @notice The proxy contract instances
    TransparentUpgradeableProxy public aclProxy;
    TransparentUpgradeableProxy public stakeManagerProxy;
    TransparentUpgradeableProxy public jobsManagerProxy;
    TransparentUpgradeableProxy public voteManagerProxy;
    TransparentUpgradeableProxy public blockManagerProxy;

    /// @notice The main function to run the deployment script
    /// @dev This function deploys all contracts, initializes them, and logs their addresses
    function run() external {
        console.log("Deployer Address : ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        deployContracts();
        initializeACL();
        // initializeOtherContracts();

        vm.stopBroadcast();

        logAddresses();
    }

    /// @notice Deploys all the contracts and their proxies
    /// @dev This function deploys the implementation contracts and their corresponding proxies
    function deployContracts() internal {
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

    /// @notice Initializes the ACL contract
    /// @dev This function sets up the initial roles for the ACL contract
    function initializeACL() internal {
        ACL acl = ACL(address(aclProxy));
        acl.initialize(deployer);  // Initialize the ACL contract
        bytes32 adminRole = acl.DEFAULT_ADMIN_ROLE();
        acl.grantRole(adminRole, address(stakeManagerProxy));
        acl.grantRole(adminRole, address(jobsManagerProxy));
        acl.grantRole(adminRole, address(voteManagerProxy));
        acl.grantRole(adminRole, address(blockManagerProxy));
    }

    /// @notice Initializes other core contracts
    /// @dev This function initializes StakeManager, JobsManager, VoteManager, and BlockManager
    function initializeOtherContracts() internal {
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
            10 ether
        );
    }

    /// @notice Logs the addresses of all deployed contracts
    /// @dev This function prints the addresses of all proxies and the ProxyAdmin
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