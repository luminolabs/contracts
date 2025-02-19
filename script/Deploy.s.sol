// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "../lib/forge-std/src/Base.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {StdChains} from "../lib/forge-std/src/StdChains.sol";
import {StdCheatsSafe} from "../lib/forge-std/src/StdCheats.sol";
import {StdUtils} from "../lib/forge-std/src/StdUtils.sol";
import {console} from "../lib/forge-std/src/console.sol";

import {AccessManager} from "../src/AccessManager.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {IncentiveManager} from "../src/IncentiveManager.sol";
import {IncentiveTreasury} from "../src/IncentiveTreasury.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {JobManager} from "../src/JobManager.sol";
import {LeaderManager} from "../src/LeaderManager.sol";
import {LuminoToken} from "../src/LuminoToken.sol";
import {NodeEscrow} from "../src/NodeEscrow.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {WhitelistManager} from "../src/WhitelistManager.sol";
import {LShared} from "../src/libraries/LShared.sol";

contract DeploymentScript is Script {
    // Contract instances
    LuminoToken public token;
    AccessManager public accessManager;
    WhitelistManager public whitelistManager;
    EpochManager public epochManager;
    NodeEscrow public nodeEscrow;
    NodeManager public nodeManager;
    JobEscrow public jobEscrow;
    JobManager public jobManager;
    LeaderManager public leaderManager;
    IncentiveTreasury public incentiveTreasury;
    IncentiveManager public incentiveManager;

    function run() external {
        // Get deployment private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy core contracts
        token = new LuminoToken();
        accessManager = new AccessManager();

        // 2. Deploy contracts with single dependencies
        whitelistManager = new WhitelistManager(
            address(accessManager)
        );

        epochManager = new EpochManager();

        // 3. Deploy escrow contracts
        nodeEscrow = new NodeEscrow(
            address(accessManager),
            address(token)
        );

        jobEscrow = new JobEscrow(
            address(accessManager),
            address(token)
        );

        incentiveTreasury = new IncentiveTreasury(
            address(token),
            address(accessManager)
        );

        // 4. Deploy node and job management
        nodeManager = new NodeManager(
            address(nodeEscrow),
            address(whitelistManager),
            address(accessManager)
        );

        // 5. Deploy leader manager
        leaderManager = new LeaderManager(
            address(epochManager),
            address(nodeManager),
            address(nodeEscrow),
            address(accessManager),
            address(whitelistManager)
        );

        // 6. Deploy job manager after leader manager
        jobManager = new JobManager(
            address(nodeManager),
            address(leaderManager),
            address(epochManager),
            address(jobEscrow),
            address(accessManager)
        );

        // 7. Finally deploy incentive manager
        incentiveManager = new IncentiveManager(
            address(epochManager),
            address(leaderManager),
            address(jobManager),
            address(nodeManager),
            address(nodeEscrow),
            address(incentiveTreasury)
        );

        // 8. Set up roles
        // Grant CONTRACTS_ROLE to contracts that need it
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(nodeEscrow));
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(jobEscrow));
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(incentiveTreasury));
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(incentiveManager));

        // Grant OPERATOR_ROLE to deployer
        accessManager.grantRole(LShared.OPERATOR_ROLE, msg.sender);

        // End broadcast
        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Deployment completed. Contract addresses:");
        console.log("LuminoToken:", address(token));
        console.log("AccessManager:", address(accessManager));
        console.log("WhitelistManager:", address(whitelistManager));
        console.log("EpochManager:", address(epochManager));
        console.log("NodeEscrow:", address(nodeEscrow));
        console.log("JobEscrow:", address(jobEscrow));
        console.log("NodeManager:", address(nodeManager));
        console.log("JobManager:", address(jobManager));
        console.log("LeaderManager:", address(leaderManager));
        console.log("IncentiveTreasury:", address(incentiveTreasury));
        console.log("IncentiveManager:", address(incentiveManager));
    }
}