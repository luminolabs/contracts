// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/RoleManager.sol";
import "../src/AccessController.sol";
import "../src/WhitelistManager.sol";
import "../src/StakingCore.sol";
import "../src/NodeStakingManager.sol";
import "../src/NodeRegistryCore.sol";
import "../src/EpochManagerCore.sol";
import "../src/LeaderElectionManager.sol";
import "../src/JobRegistry.sol";
import "../src/JobAssignmentManager.sol";
import "../src/JobPaymentManager.sol";
import "../src/JobPaymentEscrow.sol";
import "../src/RewardManager.sol";
import "../src/RewardVault.sol";
import "../src/PenaltyManager.sol";

contract DeployScript is Script {
    // Configuration constants
    uint256 public constant INITIAL_REWARD_RATE = 100 ether;
    uint256 public constant INITIAL_PENALTY_RATE = 10; // 10%
    uint256 public constant INITIAL_SLASH_THRESHOLD = 3;
    uint256 public constant INITIAL_BASE_FEE = 0.1 ether;
    uint256 public constant INITIAL_RATING_MULTIPLIER = 0.01 ether;

    // Contract instances
    RoleManager public roleManager;
    AccessController public accessController;
    WhitelistManager public whitelistManager;
    StakingCore public stakingCore;
    NodeStakingManager public nodeStakingManager;
    NodeRegistryCore public nodeRegistryCore;
    EpochManagerCore public epochManagerCore;
    LeaderElectionManager public leaderElectionManager;
    JobRegistry public jobRegistry;
    JobAssignmentManager public jobAssignmentManager;
    JobPaymentManager public jobPaymentManager;
    JobPaymentEscrow public jobPaymentEscrow;
    RewardManager public rewardManager;
    RewardVault public rewardVault;
    PenaltyManager public penaltyManager;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address stakingToken = vm.envAddress("STAKING_TOKEN_ADDRESS");
        address rewardToken = vm.envAddress("REWARD_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy core access control
        roleManager = new RoleManager();
        accessController = new AccessController(
            address(roleManager),
            address(0) // Temporarily set to 0, will update after WhitelistManager deployment
        );

        // 2. Deploy WhitelistManager and update AccessController
        whitelistManager = new WhitelistManager(address(roleManager));
        // Update WhitelistManager in AccessController using a function we'll need to add

        // 3. Deploy staking contracts
        stakingCore = new StakingCore(
            stakingToken,
            address(whitelistManager),
            address(accessController)
        );
        nodeStakingManager = new NodeStakingManager(
            address(stakingCore),
            address(0) // Will update after NodeRegistryCore deployment
        );

        // 4. Deploy node management
        nodeRegistryCore = new NodeRegistryCore(
            address(nodeStakingManager),
            address(whitelistManager),
            address(accessController)
        );
        // Update NodeRegistryCore in NodeStakingManager

        // 5. Deploy epoch and leader election
        epochManagerCore = new EpochManagerCore(address(accessController));
        leaderElectionManager = new LeaderElectionManager(
            address(epochManagerCore),
            address(nodeRegistryCore),
            address(stakingCore),
            address(accessController)
        );

        // 6. Deploy job management
        jobPaymentEscrow = new JobPaymentEscrow(address(accessController));
        jobPaymentManager = new JobPaymentManager(
            address(0), // Will update after JobRegistry deployment
            address(nodeRegistryCore),
            address(jobPaymentEscrow),
            address(accessController),
            INITIAL_BASE_FEE,
            INITIAL_RATING_MULTIPLIER
        );

        jobRegistry = new JobRegistry(
            address(jobPaymentManager),
            address(nodeRegistryCore),
            address(jobPaymentEscrow),
            address(accessController)
        );

        jobAssignmentManager = new JobAssignmentManager(
            address(jobRegistry),
            address(nodeRegistryCore),
            address(leaderElectionManager),
            address(epochManagerCore),
            1 hours // Assignment timeout
        );

        // 7. Deploy reward system
        rewardVault = new RewardVault(
            rewardToken,
            address(accessController),
            INITIAL_REWARD_RATE,
            INITIAL_REWARD_RATE,
            INITIAL_REWARD_RATE
        );

        rewardManager = new RewardManager(
            address(epochManagerCore),
            address(rewardVault),
            address(accessController)
        );

        // 8. Deploy penalty system
        penaltyManager = new PenaltyManager(
            address(stakingCore),
            stakingToken,
            treasury,
            address(accessController),
            INITIAL_PENALTY_RATE,
            INITIAL_SLASH_THRESHOLD
        );

        // Setup roles
        setupRoles();

        // Setup contract permissions
        postSetupContracts();

        vm.stopBroadcast();
    }

    function setupRoles() internal {
        // Grant ADMIN_ROLE
        bytes32 adminRole = keccak256("ADMIN_ROLE");
        roleManager.grantRole(adminRole, msg.sender);

        // Grant OPERATOR_ROLE to specified addresses
        bytes32 operatorRole = keccak256("OPERATOR_ROLE");
        address[] memory operators = getOperators();
        for (uint256 i = 0; i < operators.length; i++) {
            roleManager.grantRole(operatorRole, operators[i]);
        }

        // Grant CONTRACTS_ROLE to all core contracts
        bytes32 contractsRole = keccak256("CONTRACTS_ROLE");
        grantContractsRole(contractsRole);
    }

    function postSetupContracts() internal {
        // Link JobPaymentManager with JobRegistry
        jobPaymentManager.updateJobRegistry(address(jobRegistry));

        // Link NodeStakingManager with NodeRegistryCore
        nodeStakingManager.updateNodeRegistry(address(nodeRegistryCore));
    }

    function grantContractsRole(bytes32 contractsRole) internal {
        address[] memory contracts = new address[](8);
        contracts[0] = address(jobAssignmentManager);
        contracts[1] = address(jobPaymentManager);
        contracts[2] = address(nodeStakingManager);
        contracts[3] = address(penaltyManager);
        contracts[4] = address(rewardManager);
        contracts[5] = address(jobPaymentEscrow);
        contracts[6] = address(leaderElectionManager);
        contracts[7] = address(nodeRegistryCore);

        for (uint256 i = 0; i < contracts.length; i++) {
            roleManager.grantRole(contractsRole, contracts[i]);
        }
    }

    function getOperators() internal pure returns (address[] memory) {
        // In production, this would return a list of operator addresses
        // For testing, we'll return an empty array
        return new address[](0);
    }
}