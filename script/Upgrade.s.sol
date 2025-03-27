// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "../lib/forge-std/src/Base.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {StdChains} from "../lib/forge-std/src/StdChains.sol";
import {StdCheatsSafe} from "../lib/forge-std/src/StdCheats.sol";
import {StdUtils} from "../lib/forge-std/src/StdUtils.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccessManager} from "../src/AccessManager.sol";
import {IncentiveManager} from "../src/IncentiveManager.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {JobManager} from "../src/JobManager.sol";
import {LeaderManager} from "../src/LeaderManager.sol";
import {LuminoToken} from "../src/LuminoToken.sol";
import {NodeEscrow} from "../src/NodeEscrow.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {WhitelistManager} from "../src/WhitelistManager.sol";

/**
 * @title UpgradeScript
 * @notice Script to upgrade implementations of proxies without changing proxy addresses
 * @dev This script allows upgrading one or multiple contract implementations
 */
contract UpgradeScript is Script {
    // ProxyAdmin address (manages all proxies)
    address public proxyAdminAddress;

    // Current proxy addresses
    address public tokenProxy;
    address public accessManagerProxy;
    address public whitelistManagerProxy;
    address public nodeEscrowProxy;
    address public nodeManagerProxy;
    address public jobEscrowProxy;
    address public jobManagerProxy;
    address public leaderManagerProxy;
    address public incentiveManagerProxy;

    // Control which contracts to upgrade
    bool public upgradeToken;
    bool public upgradeAccessManager;
    bool public upgradeWhitelistManager;
    bool public upgradeNodeEscrow;
    bool public upgradeNodeManager;
    bool public upgradeJobEscrow;
    bool public upgradeJobManager;
    bool public upgradeLeaderManager;
    bool public upgradeIncentiveManager;

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Load proxy addresses from environment variables or hardcode them here
        proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        tokenProxy = vm.envAddress("TOKEN_PROXY_ADDRESS");
        accessManagerProxy = vm.envAddress("ACCESS_MANAGER_PROXY_ADDRESS");
        whitelistManagerProxy = vm.envAddress("WHITELIST_MANAGER_PROXY_ADDRESS");
        nodeEscrowProxy = vm.envAddress("NODE_ESCROW_PROXY_ADDRESS");
        nodeManagerProxy = vm.envAddress("NODE_MANAGER_PROXY_ADDRESS");
        jobEscrowProxy = vm.envAddress("JOB_ESCROW_PROXY_ADDRESS");
        jobManagerProxy = vm.envAddress("JOB_MANAGER_PROXY_ADDRESS");
        leaderManagerProxy = vm.envAddress("LEADER_MANAGER_PROXY_ADDRESS");
        incentiveManagerProxy = vm.envAddress("INCENTIVE_MANAGER_PROXY_ADDRESS");

        // Set which contracts to upgrade (typically you would modify these flags based on what needs upgrading)
        upgradeToken = vm.envBool("UPGRADE_TOKEN");
        upgradeAccessManager = vm.envBool("UPGRADE_ACCESS_MANAGER");
        upgradeWhitelistManager = vm.envBool("UPGRADE_WHITELIST_MANAGER");
        upgradeNodeEscrow = vm.envBool("UPGRADE_NODE_ESCROW");
        upgradeNodeManager = vm.envBool("UPGRADE_NODE_MANAGER");
        upgradeJobEscrow = vm.envBool("UPGRADE_JOB_ESCROW");
        upgradeJobManager = vm.envBool("UPGRADE_JOB_MANAGER");
        upgradeLeaderManager = vm.envBool("UPGRADE_LEADER_MANAGER");
        upgradeIncentiveManager = vm.envBool("UPGRADE_INCENTIVE_MANAGER");

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // Get ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Deploy new implementations and upgrade proxies based on flags
        if (upgradeToken) {
            LuminoToken newTokenImpl = new LuminoToken();
            // Empty data since we don't need to call any function during upgrade
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(tokenProxy), 
                address(newTokenImpl), 
                bytes("")
            );
            console.log("LuminoToken upgraded to new implementation:", address(newTokenImpl));
        }

        if (upgradeAccessManager) {
            AccessManager newAccessManagerImpl = new AccessManager();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(accessManagerProxy), 
                address(newAccessManagerImpl), 
                bytes("")
            );
            console.log("AccessManager upgraded to new implementation:", address(newAccessManagerImpl));
        }

        if (upgradeWhitelistManager) {
            WhitelistManager newWhitelistManagerImpl = new WhitelistManager();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(whitelistManagerProxy), 
                address(newWhitelistManagerImpl), 
                bytes("")
            );
            console.log("WhitelistManager upgraded to new implementation:", address(newWhitelistManagerImpl));
        }

        if (upgradeNodeEscrow) {
            NodeEscrow newNodeEscrowImpl = new NodeEscrow();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(nodeEscrowProxy), 
                address(newNodeEscrowImpl), 
                bytes("")
            );
            console.log("NodeEscrow upgraded to new implementation:", address(newNodeEscrowImpl));
        }

        if (upgradeNodeManager) {
            NodeManager newNodeManagerImpl = new NodeManager();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(nodeManagerProxy), 
                address(newNodeManagerImpl), 
                bytes("")
            );
            console.log("NodeManager upgraded to new implementation:", address(newNodeManagerImpl));
        }

        if (upgradeJobEscrow) {
            JobEscrow newJobEscrowImpl = new JobEscrow();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(jobEscrowProxy), 
                address(newJobEscrowImpl), 
                bytes("")
            );
            console.log("JobEscrow upgraded to new implementation:", address(newJobEscrowImpl));
        }

        if (upgradeJobManager) {
            JobManager newJobManagerImpl = new JobManager();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(jobManagerProxy), 
                address(newJobManagerImpl), 
                bytes("")
            );
            console.log("JobManager upgraded to new implementation:", address(newJobManagerImpl));
        }

        if (upgradeLeaderManager) {
            LeaderManager newLeaderManagerImpl = new LeaderManager();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(leaderManagerProxy), 
                address(newLeaderManagerImpl), 
                bytes("")
            );
            console.log("LeaderManager upgraded to new implementation:", address(newLeaderManagerImpl));
        }

        if (upgradeIncentiveManager) {
            IncentiveManager newIncentiveManagerImpl = new IncentiveManager();
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(incentiveManagerProxy), 
                address(newIncentiveManagerImpl), 
                bytes("")
            );
            console.log("IncentiveManager upgraded to new implementation:", address(newIncentiveManagerImpl));
        }

        // End broadcast
        vm.stopBroadcast();
    }
}