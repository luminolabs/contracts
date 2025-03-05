// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "../lib/forge-std/src/Base.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {StdChains} from "../lib/forge-std/src/StdChains.sol";
import {StdCheatsSafe} from "../lib/forge-std/src/StdCheats.sol";
import {StdUtils} from "../lib/forge-std/src/StdUtils.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {AccessManager} from "../src/AccessManager.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {IncentiveManager} from "../src/IncentiveManager.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {JobManager} from "../src/JobManager.sol";
import {LeaderManager} from "../src/LeaderManager.sol";
import {LuminoToken} from "../src/LuminoToken.sol";
import {NodeEscrow} from "../src/NodeEscrow.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {WhitelistManager} from "../src/WhitelistManager.sol";
import {LShared} from "../src/libraries/LShared.sol";

contract DeploymentScript is Script {
    // Contract implementations
    LuminoToken public tokenImpl;
    AccessManager public accessManagerImpl;
    WhitelistManager public whitelistManagerImpl;
    EpochManager public epochManagerImpl;
    NodeEscrow public nodeEscrowImpl;
    NodeManager public nodeManagerImpl;
    JobEscrow public jobEscrowImpl;
    JobManager public jobManagerImpl;
    LeaderManager public leaderManagerImpl;
    IncentiveManager public incentiveManagerImpl;

    // Proxy admin
    ProxyAdmin public proxyAdmin;

    // Proxies (the actual contract addresses users will interact with)
    address public tokenProxy;
    address public accessManagerProxy;
    address public whitelistManagerProxy;
    address public epochManagerProxy;
    address public nodeEscrowProxy;
    address public nodeManagerProxy;
    address public jobEscrowProxy;
    address public jobManagerProxy;
    address public leaderManagerProxy;
    address public incentiveManagerProxy;

    function run() external {
        // Get deployment private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // Deploy ProxyAdmin first - this will manage all proxies
        proxyAdmin = new ProxyAdmin(msg.sender);
        console.log("ProxyAdmin:", address(proxyAdmin));

        // 1. Deploy implementations
        tokenImpl = new LuminoToken();
        accessManagerImpl = new AccessManager();
        whitelistManagerImpl = new WhitelistManager();
        epochManagerImpl = new EpochManager();
        nodeEscrowImpl = new NodeEscrow();
        jobEscrowImpl = new JobEscrow();
        nodeManagerImpl = new NodeManager();
        leaderManagerImpl = new LeaderManager();
        incentiveManagerImpl = new IncentiveManager();

        // 2. Deploy and initialize proxies

        // LuminoToken proxy
        tokenProxy = deployProxy(
            address(tokenImpl),
            abi.encodeWithSelector(
                LuminoToken.initialize.selector
            )
        );

        // AccessManager proxy
        accessManagerProxy = deployProxy(
            address(accessManagerImpl),
            abi.encodeWithSelector(
                AccessManager.initialize.selector
            )
        );

        // WhitelistManager proxy
        whitelistManagerProxy = deployProxy(
            address(whitelistManagerImpl),
            abi.encodeWithSelector(
                WhitelistManager.initialize.selector,
                accessManagerProxy
            )
        );

        // EpochManager proxy
        epochManagerProxy = deployProxy(
            address(epochManagerImpl),
            abi.encodeWithSelector(
                EpochManager.initialize.selector
            )
        );

        // NodeEscrow proxy
        nodeEscrowProxy = deployProxy(
            address(nodeEscrowImpl),
            abi.encodeWithSelector(
                NodeEscrow.initialize.selector,
                accessManagerProxy,
                tokenProxy
            )
        );

        // JobEscrow proxy
        jobEscrowProxy = deployProxy(
            address(jobEscrowImpl),
            abi.encodeWithSelector(
                JobEscrow.initialize.selector,
                accessManagerProxy,
                tokenProxy
            )
        );

        // NodeManager proxy
        nodeManagerProxy = deployProxy(
            address(nodeManagerImpl),
            abi.encodeWithSelector(
                NodeManager.initialize.selector,
                nodeEscrowProxy,
                whitelistManagerProxy,
                accessManagerProxy
            )
        );

        // LeaderManager proxy
        leaderManagerProxy = deployProxy(
            address(leaderManagerImpl),
            abi.encodeWithSelector(
                LeaderManager.initialize.selector,
                epochManagerProxy,
                nodeManagerProxy,
                nodeEscrowProxy,
                accessManagerProxy,
                whitelistManagerProxy
            )
        );

        // JobManager proxy
        jobManagerProxy = deployProxy(
            address(jobManagerImpl),
            abi.encodeWithSelector(
                JobManager.initialize.selector,
                nodeManagerProxy,
                leaderManagerProxy,
                epochManagerProxy,
                jobEscrowProxy,
                accessManagerProxy
            )
        );

        // IncentiveManager proxy
        incentiveManagerProxy = deployProxy(
            address(incentiveManagerImpl),
            abi.encodeWithSelector(
                IncentiveManager.initialize.selector,
                epochManagerProxy,
                leaderManagerProxy,
                jobManagerProxy,
                nodeManagerProxy,
                nodeEscrowProxy
            )
        );

        // 3. Set up roles
        // Create interface instances to interact with the proxies
        AccessManager accessManager = AccessManager(accessManagerProxy);

        // Grant CONTRACTS_ROLE to contracts that need it
        accessManager.grantRole(LShared.CONTRACTS_ROLE, incentiveManagerProxy);
        accessManager.grantRole(LShared.CONTRACTS_ROLE, jobManagerProxy);

        // Grant OPERATOR_ROLE to deployer
        accessManager.grantRole(LShared.OPERATOR_ROLE, msg.sender);

        // End broadcast
        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Deployment completed. Contract addresses:");
        console.log("LuminoToken (Implementation):", address(tokenImpl));
        console.log("LuminoToken (Proxy):", tokenProxy);
        console.log("AccessManager (Implementation):", address(accessManagerImpl));
        console.log("AccessManager (Proxy):", accessManagerProxy);
        console.log("WhitelistManager (Implementation):", address(whitelistManagerImpl));
        console.log("WhitelistManager (Proxy):", whitelistManagerProxy);
        console.log("EpochManager (Implementation):", address(epochManagerImpl));
        console.log("EpochManager (Proxy):", epochManagerProxy);
        console.log("NodeEscrow (Implementation):", address(nodeEscrowImpl));
        console.log("NodeEscrow (Proxy):", nodeEscrowProxy);
        console.log("JobEscrow (Implementation):", address(jobEscrowImpl));
        console.log("JobEscrow (Proxy):", jobEscrowProxy);
        console.log("NodeManager (Implementation):", address(nodeManagerImpl));
        console.log("NodeManager (Proxy):", nodeManagerProxy);
        console.log("JobManager (Implementation):", address(jobManagerImpl));
        console.log("JobManager (Proxy):", jobManagerProxy);
        console.log("LeaderManager (Implementation):", address(leaderManagerImpl));
        console.log("LeaderManager (Proxy):", leaderManagerProxy);
        console.log("IncentiveManager (Implementation):", address(incentiveManagerImpl));
        console.log("IncentiveManager (Proxy):", incentiveManagerProxy);
    }

    // Helper function to deploy a proxy
    function deployProxy(address implementation, bytes memory data) internal returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation,
            address(proxyAdmin),
            data
        );
        return address(proxy);
    }
}