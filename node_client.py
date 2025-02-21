import logging
import os
import random
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from eth_account import Account
from web3.contract import Contract

# Load environment variables
load_dotenv()

import json
from typing import Dict, List
from web3 import Web3
from web3.exceptions import ContractLogicError
from eth_abi import decode


class LuminoErrorHandler:
    """Handles decoding and formatting of Lumino contract custom errors"""

    # Enum mappings
    JOB_STATUS = {
        0: "NEW",
        1: "ASSIGNED",
        2: "CONFIRMED",
        3: "COMPLETE"
    }

    EPOCH_STATE = {
        0: "COMMIT",
        1: "REVEAL",
        2: "ELECT",
        3: "EXECUTE",
        4: "CONFIRM",
        5: "DISPUTE",
        6: "PAUSED"
    }

    def __init__(self):
        # Error definitions with their parameter types and formatters
        self.error_defs = {
            # AccessManager errors
            "RoleManagerUnauthorized": {
                "params": ["address"],
                "format": lambda args: f"Account {args[0]} is not authorized for this role"
            },
            "InvalidRole": {
                "params": ["bytes32"],
                "format": lambda args: f"Invalid role: {args[0].hex()}"
            },
            "CannotRevokeAdmin": {
                "params": [],
                "format": lambda args: "Cannot revoke the last admin role"
            },
            "MustConfirmRenounce": {
                "params": ["address"],
                "format": lambda args: f"Account {args[0]} must confirm renounce"
            },

            # EpochManager errors
            "InvalidState": {
                "params": ["uint8"],
                "format": lambda args: f"Invalid epoch state: {self.EPOCH_STATE.get(args[0], 'Unknown')}"
            },

            # Escrow (AEscrow) errors
            "BelowMinimumDeposit": {
                "params": ["uint256", "uint256"],
                "format": lambda
                    args: f"Deposit amount {Web3.from_wei(args[0], 'ether')} is below minimum required {Web3.from_wei(args[1], 'ether')}"
            },
            "InsufficientBalance": {
                "params": ["address", "uint256", "uint256"],
                "format": lambda
                    args: f"Insufficient balance for {args[0]}: requested {Web3.from_wei(args[1], 'ether')}, available {Web3.from_wei(args[2], 'ether')}"
            },
            "ExistingWithdrawRequest": {
                "params": ["address"],
                "format": lambda args: f"Active withdrawal request already exists for {args[0]}"
            },
            "NoWithdrawRequest": {
                "params": ["address"],
                "format": lambda args: f"No active withdrawal request found for {args[0]}"
            },
            "LockPeriodActive": {
                "params": ["address", "uint256"],
                "format": lambda args: f"Lock period still active for {args[0]}, {args[1]} seconds remaining"
            },
            "TransferFailed": {
                "params": [],
                "format": lambda args: "Token transfer failed"
            },
            "InsufficientContractBalance": {
                "params": ["uint256", "uint256"],
                "format": lambda
                    args: f"Contract balance insufficient: requested {Web3.from_wei(args[0], 'ether')}, available {Web3.from_wei(args[1], 'ether')}"
            },

            # JobManager errors
            "InvalidJobStatus": {
                "params": ["uint256", "uint8", "uint8"],
                "format": lambda
                    args: f"Invalid job status for job {args[0]}: current {self.JOB_STATUS.get(args[1], 'Unknown')}, attempted {self.JOB_STATUS.get(args[2], 'Unknown')}"
            },
            "InvalidStatusTransition": {
                "params": ["uint8", "uint8"],
                "format": lambda
                    args: f"Invalid job status transition from {self.JOB_STATUS.get(args[0], 'Unknown')} to {self.JOB_STATUS.get(args[1], 'Unknown')}"
            },
            "JobAlreadyProcessed": {
                "params": ["uint256"],
                "format": lambda args: f"Job {args[0]} has already been processed"
            },
            "JobNotComplete": {
                "params": ["uint256"],
                "format": lambda args: f"Job {args[0]} is not in completed state"
            },
            "InvalidModelName": {
                "params": ["string"],
                "format": lambda args: f"Invalid model name: {args[0]}"
            },

            # LeaderManager errors
            "NoCommitmentFound": {
                "params": ["uint256", "uint256"],
                "format": lambda args: f"No commitment found for epoch {args[0]}, node {args[1]}"
            },
            "InvalidSecret": {
                "params": ["uint256"],
                "format": lambda args: f"Invalid secret revealed for node {args[0]}"
            },
            "NoRevealsSubmitted": {
                "params": ["uint256"],
                "format": lambda args: f"No secrets revealed for epoch {args[0]}"
            },
            "MissingReveal": {
                "params": ["uint256"],
                "format": lambda args: f"Missing secret reveal from node {args[0]}"
            },
            "NotCurrentLeader": {
                "params": ["address", "address"],
                "format": lambda args: f"Account {args[0]} is not the current leader (leader is {args[1]})"
            },
            "NoRandomValueForEpoch": {
                "params": ["uint256"],
                "format": lambda args: f"No random value available for epoch {args[0]}"
            },
            "LeaderAlreadyElected": {
                "params": ["uint256"],
                "format": lambda args: f"Leader already elected for epoch {args[0]}"
            },

            # NodeManager errors
            "NodeNotFound": {
                "params": ["uint256"],
                "format": lambda args: f"Node {args[0]} not found"
            },
            "NodeNotActive": {
                "params": ["uint256"],
                "format": lambda args: f"Node {args[0]} is not active"
            },
            "InsufficientStake": {
                "params": ["address", "uint256"],
                "format": lambda args: f"Insufficient stake for {args[0]} with compute rating {args[1]}"
            },
            "InvalidNodeOwner": {
                "params": ["uint256", "address"],
                "format": lambda args: f"Invalid node owner: {args[1]} does not own node {args[0]}"
            },

            # WhitelistManager errors
            "AlreadyWhitelisted": {
                "params": ["address"],
                "format": lambda args: f"Computing provider {args[0]} is already whitelisted"
            },
            "CooldownActive": {
                "params": ["address", "uint256"],
                "format": lambda args: f"Cooldown period active for {args[0]}, {args[1]} seconds remaining"
            },
            "NotWhitelisted": {
                "params": ["address"],
                "format": lambda args: f"Computing provider {args[0]} is not whitelisted"
            },

            # IncentiveManager errors
            "EpochAlreadyProcessed": {
                "params": ["uint256"],
                "format": lambda args: f"Epoch incentives has already been processed, got epoch {args[0]}"
            }
        }

        # Generate error selectors using web3
        self.error_selectors = {}
        w3 = Web3()
        for error_name, error_def in self.error_defs.items():
            # Create the error signature
            params_str = ",".join(error_def["params"])
        signature = f"{error_name}({params_str})"

        # Generate the selector
        selector = w3.keccak(text=signature)[:4].hex()
        self.error_selectors[selector] = (error_name, error_def)

    def decode_error(self, error_data: str) -> str:
        """
        Decodes a contract custom error into a human-readable message

        Args:
            error_data: The hex string of the error selector and data

        Returns:
            A human-readable error message
        """
        try:
            # Clean up error data if needed
            if isinstance(error_data, tuple):
                error_data = error_data[0]
            if error_data.startswith("execution reverted: "):
                error_data = error_data.split("execution reverted: ")[1]

            # Extract the selector (first 4 bytes)
            if error_data.startswith("0x"):
                selector = error_data[2:10]
            else:
                selector = error_data[:8]

            # Look up the error information
            if selector in self.error_selectors:
                error_name, error_def = self.error_selectors[selector]

                # If no parameters, return the basic message
                if not error_def["params"]:
                    return error_def["format"]([])

                # Extract the parameter data
                param_data = error_data[10:] if error_data.startswith("0x") else error_data[8:]

                # Decode the parameters using eth_abi
                decoded_params = decode(error_def["params"], bytes.fromhex(param_data))

                # Format the error message
                return error_def["format"](decoded_params)

            return f"Unknown error selector: 0x{selector}"

        except Exception as e:
            return f"Error decoding custom error: {error_data} (Decoder error: {str(e)})"

    def decode_contract_error(self, error: ContractLogicError) -> str:
        """
        Decodes a ContractLogicError into a human-readable message

        Args:
            error: The ContractLogicError from web3.py

        Returns:
            A human-readable error message
        """
        try:
            # Extract the error data from the error message
            return self.decode_error(error.data)
        except Exception as e:
            return f"Failed to decode contract error: {str(error)} (Decoder error: {str(e)})"


@dataclass
class LuminoConfig:
    """Configuration for Lumino Node"""
    web3_provider: str
    private_key: str
    contract_addresses: Dict[str, str]
    contracts_dir: str
    data_dir: str = "../node_data"
    log_level: int = logging.INFO
    test_mode: Optional[str] = None

    @classmethod
    def from_file(cls, config_path: str) -> 'LuminoConfig':
        """Create config from JSON file"""
        with open(config_path) as f:
            config_data = json.load(f)
        return cls(**config_data)

    def save(self, config_path: str) -> None:
        """Save config to JSON file"""
        config_dict = {
            k: v for k, v in self.__dict__.items()
            if k != 'private_key'
        }
        with open(config_path, 'w') as f:
            json.dump(config_dict, f, indent=2)


class EventHandler:
    """Handles contract event processing and logging"""

    def __init__(self, logger: logging.Logger):
        self.logger = logger
        self.event_filters = {}
        self.last_processed_block = 0

    def create_event_filter(self, contract: Contract, event_name: str, from_block: int) -> None:
        """Create a new event filter for a specific contract event"""
        event = getattr(contract.events, event_name)
        event_filter = event.create_filter(from_block=from_block)
        self.event_filters[(contract.address, event_name)] = event_filter
        self.logger.info(f"Created filter for {event_name} events from block {from_block}")

    def process_events(self) -> None:
        """Process all pending events from all filters"""
        for (contract_address, event_name), event_filter in self.event_filters.items():
            try:
                for event in event_filter.get_new_entries():
                    self._log_event(event_name, event)
            except Exception as e:
                self.logger.error(f"Error processing {event_name} events: {e}")

    def _log_event(self, event_name: str, event: dict) -> None:
        """Format and log a contract event"""
        # Extract event arguments
        args = event['args']
        formatted_args = []
        for key, value in args.items():
            # Format value based on type
            if isinstance(value, bytes):
                formatted_value = value.hex()
            elif isinstance(value, int):
                # Check if it might be wei
                if key.lower().endswith(('amount', 'balance', 'stake')):
                    formatted_value = f"{Web3.from_wei(value, 'ether')} ETH"
                else:
                    formatted_value = str(value)
            else:
                formatted_value = str(value)
            formatted_args.append(f"{key}: {formatted_value}")

        # Build event message
        event_msg = f"Event {event_name} emitted:"
        for arg in formatted_args:
            event_msg += f"\n    {arg}"

        self.logger.info(event_msg)


class LuminoNode:
    def __init__(self, config: LuminoConfig):
        """Initialize the Lumino node client"""
        # Set up data directory
        self.data_dir = Path(config.data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.node_data_file = self.data_dir / "node_data.json"

        # Set test mode
        self.test_mode = config.test_mode

        # Setup error handler
        self.error_handler = LuminoErrorHandler()

        # Set up logging
        self._setup_logging(config.log_level)
        self.logger.info("Initializing Lumino Node...")

        # Initialize Web3 and account
        self.logger.info(f"Connecting to Web3 provider: {config.web3_provider}")
        self.w3 = Web3(Web3.HTTPProvider(config.web3_provider))
        if not self.w3.is_connected():
            raise ConnectionError(f"Failed to connect to {config.web3_provider}")

        self.account = Account.from_key(config.private_key)
        self.address = self.account.address

        # Load node data
        self.node_data = self._load_node_data()
        self.node_id = self.node_data.get("node_id")

        # Load ABIs and initialize contracts
        self.abis = self._load_abis(config.contracts_dir)
        self._init_contracts(config.contract_addresses)

        # Initialize event handler
        self.event_handler = EventHandler(self.logger)
        self._setup_event_filters()

        # Node state
        self.current_secret: Optional[bytes] = None
        self.current_commitment: Optional[bytes] = None
        self.is_leader = False

        self.logger.info("Lumino Node initialization complete")

    def _setup_event_filters(self) -> None:
        """Set up filters for all relevant contract events"""
        current_block = self.w3.eth.block_number

        # AccessManager events
        self._create_event_filters(self.access_manager, [
            'RoleGranted',
            'RoleRevoked'
        ], current_block)

        # NodeManager events
        self._create_event_filters(self.node_manager, [
            'NodeRegistered',
            'NodeUnregistered',
            'NodeUpdated',
            'StakeValidated',
            'StakeRequirementUpdated'
        ], current_block)

        # LeaderManager events
        self._create_event_filters(self.leader_manager, [
            'CommitSubmitted',
            'SecretRevealed',
            'LeaderElected'
        ], current_block)

        # JobManager events
        self._create_event_filters(self.job_manager, [
            'JobSubmitted',
            'JobStatusUpdated',
            'JobAssigned',
            'AssignmentRoundStarted',
            'JobConfirmed',
            'JobCompleted',
            'JobRejected',
            'PaymentProcessed'
        ], current_block)

        # NodeEscrow events
        self._create_event_filters(self.node_escrow, [
            'Deposited',
            'WithdrawRequested',
            'WithdrawCancelled',
            'Withdrawn',
            'PenaltyApplied',
            'SlashApplied',
            'RewardApplied'
        ], current_block)

        # JobEscrow events
        self._create_event_filters(self.job_escrow, [
            'Deposited',
            'WithdrawRequested',
            'WithdrawCancelled',
            'Withdrawn',
            'PaymentReleased'
        ], current_block)

        # WhitelistManager events
        self._create_event_filters(self.whitelist_manager, [
            'CPAdded',
            'CPRemoved'
        ], current_block)

        # LuminoToken events (ERC20)
        self._create_event_filters(self.token, [
            'Transfer',
            'Approval'
        ], current_block)

        # IncentiveManager events
        self._create_event_filters(self.incentive_manager, [
            'LeaderRewardApplied',
            'JobAvailabilityRewardApplied',
            'DisputerRewardApplied',
            'LeaderNotExecutedPenaltyApplied',
            'JobNotConfirmedPenaltyApplied'
        ], current_block)

    def _create_event_filters(self, contract: Contract, event_names: List[str], from_block: int) -> None:
        """Create filters for multiple events from a contract"""
        for event_name in event_names:
            self.event_handler.create_event_filter(contract, event_name, from_block)

    def _check_for_events(self) -> None:
        """Process any new events"""
        self.event_handler.process_events()

    def _setup_logging(self, log_level: int) -> None:
        """Set up logging with file and console handlers"""
        self.logger = logging.getLogger("LuminoNode")
        self.logger.setLevel(log_level)

        # Remove existing handlers if any
        for handler in self.logger.handlers[:]:
            self.logger.removeHandler(handler)

        # Create formatters and handlers
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )

        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        self.logger.addHandler(console_handler)

        # File handler
        file_handler = logging.FileHandler(
            self.data_dir / "lumino_node.log"
        )
        file_handler.setFormatter(formatter)
        self.logger.addHandler(file_handler)

    def _load_abis(self, contracts_dir: str) -> Dict[str, dict]:
        """
        Load contract ABIs from Foundry output directory

        Args:
            contracts_dir: Path to the contracts directory (src/)

        Returns:
            Dict mapping contract names to their ABIs
        """
        abis = {}
        out_dir = os.path.join(os.path.dirname(contracts_dir), 'out')

        if not os.path.exists(out_dir):
            raise FileNotFoundError(
                f"Foundry output directory not found at {out_dir}. "
                "Please run 'forge build' first."
            )

        # Walk through the out directory
        for root, dirs, files in os.walk(out_dir):
            for file in files:
                if file.endswith('.json'):
                    file_path = os.path.join(root, file)

                    # Extract contract name from the path
                    # The structure is out/<ContractName>.sol/<ContractName>.json
                    contract_name = os.path.basename(root).replace('.sol', '')

                    # Skip test contracts
                    if contract_name.endswith('.t'):
                        continue

                    try:
                        with open(file_path, 'r') as f:
                            contract_data = json.load(f)
                            if 'abi' in contract_data:
                                abis[contract_name] = contract_data['abi']
                                self.logger.debug(f"Loaded ABI for {contract_name}")
                    except Exception as e:
                        self.logger.warning(f"Failed to load ABI from {file_path}: {e}")
                        continue

        if not abis:
            raise ValueError(
                "No ABIs found in Foundry output directory. "
                "Please ensure contracts are compiled with 'forge build'."
            )

        return abis

    def _init_contracts(self, contract_addresses: Dict[str, str]) -> None:
        """Initialize all contract interfaces"""
        try:
            self.access_manager = self.w3.eth.contract(
                address=contract_addresses['AccessManager'],
                abi=self.abis['AccessManager']
            )
            self.logger.info("Initialized AccessManager contract")

            self.whitelist_manager = self.w3.eth.contract(
                address=contract_addresses['WhitelistManager'],
                abi=self.abis['WhitelistManager']
            )
            self.logger.info("Initialized WhitelistManager contract")

            self.token = self.w3.eth.contract(
                address=contract_addresses['LuminoToken'],
                abi=self.abis['LuminoToken']
            )
            self.logger.info("Initialized LuminoToken contract")

            self.incentive_manager = self.w3.eth.contract(
                address=contract_addresses['IncentiveManager'],
                abi=self.abis['IncentiveManager']
            )

            self.node_manager = self.w3.eth.contract(
                address=contract_addresses['NodeManager'],
                abi=self.abis['NodeManager']
            )
            self.logger.info("Initialized NodeManager contract")

            self.node_escrow = self.w3.eth.contract(
                address=contract_addresses['NodeEscrow'],
                abi=self.abis['NodeEscrow']
            )
            self.logger.info("Initialized NodeEscrow contract")

            self.leader_manager = self.w3.eth.contract(
                address=contract_addresses['LeaderManager'],
                abi=self.abis['LeaderManager']
            )
            self.logger.info("Initialized LeaderManager contract")

            self.job_manager = self.w3.eth.contract(
                address=contract_addresses['JobManager'],
                abi=self.abis['JobManager']
            )
            self.logger.info("Initialized JobManager contract")

            self.job_escrow = self.w3.eth.contract(
                address=contract_addresses['JobEscrow'],
                abi=self.abis['JobEscrow']
            )
            self.logger.info("Initialized JobEscrow contract")

            self.epoch_manager = self.w3.eth.contract(
                address=contract_addresses['EpochManager'],
                abi=self.abis['EpochManager']
            )
            self.logger.info("Initialized EpochManager contract")

        except Exception as e:
            self.logger.error(f"Failed to initialize contracts: {e}")
            raise

    def _load_node_data(self) -> dict:
        """Load node data from disk or initialize if not exists"""
        if self.node_data_file.exists():
            with open(self.node_data_file) as f:
                return json.load(f)
        return {}

    def _save_node_data(self) -> None:
        """Save node data to disk"""
        with open(self.node_data_file, 'w') as f:
            json.dump(self.node_data, f, indent=2)

    def approve_token_spending(self, amount) -> None:
        """Give permission to Escrow contract to handle set amount of tokens"""
        tx = self.token.functions.approve(self.node_escrow.address, amount).build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        self.w3.eth.wait_for_transaction_receipt(tx_hash)

        self.logger.info("Token spending approved for NodeEscrow")

    def stake_tokens(self, amount: int) -> None:
        """Deposit tokens into NodeEscrow as stake

        Args:
            amount: Amount of tokens to stake in wei
        """
        # First approve the transfer
        self.approve_token_spending(amount)

        # Then deposit
        tx = self.node_escrow.functions.deposit(amount).build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)

        self.logger.info(f"Staked {Web3.from_wei(amount, 'ether')} tokens")

    def register_node(self, compute_rating: int) -> None:
        """Register node with the protocol and store node ID

        First ensures sufficient stake is deposited based on compute rating
        """
        # Skip if already registered
        if self.node_id is not None:
            self.logger.info(f"Node already registered with ID: {self.node_id}")
            return

        # TODO: Get total required stake from contract, including new node

        # Calculate required stake (1 token per compute rating unit)
        required_stake = Web3.to_wei(compute_rating, 'ether')

        # Check current stake
        current_stake = self.node_escrow.functions.getBalance(self.address).call()
        if current_stake < required_stake:
            self.logger.info(f"Insufficient stake. Depositing required amount...")
            additional_stake_needed = required_stake - current_stake
            self.stake_tokens(additional_stake_needed)

        tx = self.node_manager.functions.registerNode(compute_rating).build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)

        # Get node ID from event
        node_registered_event = self.node_manager.events.NodeRegistered()
        logs = node_registered_event.process_receipt(receipt)
        self.node_id = logs[0]['args']['nodeId']

        # Save node ID to disk
        self.node_data["node_id"] = self.node_id
        self._save_node_data()

        self.logger.info(f"Node registered with ID: {self.node_id}")

    def get_current_epoch(self) -> int:
        """Get the current epoch number"""
        return self.epoch_manager.functions.getCurrentEpoch().call()

    def get_current_epoch_state(self) -> tuple:
        """Get current epoch state and time left"""
        # TODO: up test counter only in local env
        tx = self.epoch_manager.functions.upTestCounter().build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        self.w3.eth.wait_for_transaction_receipt(tx_hash)

        return self.epoch_manager.functions.getEpochState().call()

    def submit_commitment(self) -> None:
        """Submit commitment for current epoch"""
        # Generate random secret
        self.current_secret = random.randbytes(32)
        # Create commitment (hash of secret)
        # TODO: hash this again with epoch number for the final commitment
        self.current_commitment = Web3.solidity_keccak(['bytes32'], [self.current_secret])

        tx = self.leader_manager.functions.submitCommitment(
            self.node_id,
            self.current_commitment
        ).build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        self.w3.eth.wait_for_transaction_receipt(tx_hash)
        self.logger.info("Commitment submitted")

    def reveal_secret(self) -> None:
        """Reveal secret for current epoch"""
        if not self.current_secret:
            self.logger.error("No secret to reveal")
            return

        tx = self.leader_manager.functions.revealSecret(
            self.node_id,
            self.current_secret
        ).build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        self.w3.eth.wait_for_transaction_receipt(tx_hash)
        self.logger.info("Secret revealed")

    def elect_leader(self) -> None:
        """Trigger leader election for current epoch"""
        tx = self.leader_manager.functions.electLeader().build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        self.w3.eth.wait_for_transaction_receipt(tx_hash)
        self.logger.info("Leader election triggered")

    def check_and_perform_leader_duties(self) -> None:
        """Check if node is leader and perform leader duties"""
        current_leader = self.leader_manager.functions.getCurrentLeader().call()
        self.is_leader = (current_leader == self.node_id)

        if self.is_leader:
            self.logger.info("This node is the current leader")
            try:
                # Start assignment round
                tx = self.job_manager.functions.startAssignmentRound().build_transaction({
                    'from': self.address,
                    'nonce': self.w3.eth.get_transaction_count(self.address), })
                signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
                tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
                self.w3.eth.wait_for_transaction_receipt(tx_hash)
                self.logger.info("Assignment round started")
            except ContractLogicError as e:
                error_message = self.error_handler.decode_contract_error(e)
                self.logger.error(f"Contract error: {error_message}")
            except Exception as e:
                self.logger.error(f"Failed to start assignment round: {e}")
        else:
            self.logger.info("This node is not the current leader")

    def process_assigned_jobs(self) -> None:
        """Process any jobs assigned to this node"""
        # Get jobs assigned to this node
        # Note: In a real implementation, you would need to track assigned jobs
        assigned_jobs = self._get_assigned_jobs()

        for job_id, job_args in assigned_jobs.items():
            try:
                # Confirm job
                tx = self.job_manager.functions.confirmJob(job_id).build_transaction({
                    'from': self.address,
                    'nonce': self.w3.eth.get_transaction_count(self.address),
                })
                signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
                tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
                self.w3.eth.wait_for_transaction_receipt(tx_hash)
                self.logger.info(f"Confirmed job {job_id}")

                # Execute job (dummy implementation - sleep for 10 seconds)
                self._execute_job(job_id, job_args)

                # Mark job as complete
                tx = self.job_manager.functions.completeJob(job_id).build_transaction({
                    'from': self.address,
                    'nonce': self.w3.eth.get_transaction_count(self.address),
                })
                signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
                tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
                self.w3.eth.wait_for_transaction_receipt(tx_hash)
                self.logger.info(f"Completed job {job_id}")

                # TODO: Add payment processing
                # ...
            except Exception as e:
                self.logger.error(f"Error processing job {job_id}: {e}")

    def _get_assigned_jobs(self) -> Dict[int, str]:
        """Get list of jobs assigned to this node

        In a real implementation, you would need to:
        1. Track assignments from JobAssigned events
        2. Filter out completed jobs
        3. Query the contract for current assignments
        """
        try:
            job_ids, job_args = self.job_manager.functions.getJobsDetailsByNode(self.node_id).call()
            return dict(zip(job_ids, job_args))
        except Exception as e:
            self.logger.error(f"Error getting assigned jobs: {e}")
            return {}

    def _execute_job(self, job_id: int, job_args: str) -> None:
        """Execute a job

        In a real implementation, this would:
        1. Get job parameters from contract
        2. Load and run the specified model
        3. Track and report progress
        4. Handle errors and retries
        """
        self.logger.info(f"Executing job {job_id}")
        try:
            # Simulated work
            time.sleep(10)
            self.logger.info(f"Job [{job_id} : {job_args}] execution completed")
        except Exception as e:
            self.logger.error(f"Error executing job {job_id}: {e}")
            raise

    def start_incentive_cycle(self) -> None:
        """Start the incentive cycle for the current epoch"""
        tx = self.incentive_manager.functions.processAll().build_transaction({
            'from': self.address,
            'nonce': self.w3.eth.get_transaction_count(self.address),
        })
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.account.key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        self.w3.eth.wait_for_transaction_receipt(tx_hash)
        self.logger.info("Incentive cycle started")

    def run(self) -> None:
        """Main loop for the node"""
        self.logger.info("Starting main node loop...")
        self.logger.info(f"Node ID: {self.node_id}")
        self.logger.info(f"Node address: {self.address}")

        # Track phase timing
        last_phase = None
        phase_start_time = time.time()
        status_update_interval = 300  # 5 minutes
        last_status_update = time.time()

        # Map numeric states to readable names
        state_names = {
            0: "COMMIT",
            1: "REVEAL",
            2: "ELECT",
            3: "EXECUTE",
            4: "CONFIRM",
            5: "DISPUTE"
        }

        # Node can begin after first DISPUTE phase,
        # so that the cycle starts correctly from COMMIT
        can_begin = False

        epochs_processed = 0
        while True:
            try:
                current_time = time.time()

                # Periodic status update
                if current_time - last_status_update >= status_update_interval:
                    stake_balance = self.node_escrow.functions.getBalance(self.address).call()
                    token_balance = self.token.functions.balanceOf(self.address).call()
                    current_epoch = self.epoch_manager.functions.getCurrentEpoch().call()

                    self.logger.info("=== Node Status Update ===")
                    self.logger.info(f"Current epoch: {current_epoch}")
                    self.logger.info(f"Stake balance: {Web3.from_wei(stake_balance, 'ether')} LUM")
                    self.logger.info(f"Token balance: {Web3.from_wei(token_balance, 'ether')} LUM")
                    self.logger.info(f"Leader status: {'Leader' if self.is_leader else 'Regular node'}")
                    self.logger.info("========================")

                    last_status_update = current_time

                # Process any new events
                self._check_for_events()

                # Get current epoch state
                state, time_left = self.get_current_epoch_state()
                current_phase = state_names[state]

                # Log state transitions
                state_changed = last_phase != current_phase
                if state_changed:
                    if last_phase:
                        state_duration = current_time - phase_start_time
                        self.logger.info(f"Completed {last_phase} phase (duration: {state_duration:.2f}s)")
                    self.logger.info(f"Entering {current_phase} phase (time left: {time_left}s)")
                    last_phase = current_phase
                    phase_start_time = current_time

                self.logger.info(f"Can begin: {can_begin}")
                self.logger.info(f"Phase changed: {state_changed}")
                self.logger.info(f"Remaining time: {time_left:.2f}s")

                # State machine for epoch phases
                if can_begin and state_changed:
                    try:
                        if state == 0:  # COMMIT
                            self.logger.info("Preparing to submit commitment...")
                            self.submit_commitment()
                            self.logger.info("Commitment submitted successfully")

                        elif state == 1:  # REVEAL
                            if self.current_secret:
                                self.logger.info("Preparing to reveal secret...")
                                self.reveal_secret()
                                self.logger.info("Secret revealed successfully")
                            else:
                                self.logger.warning("No secret available to reveal")

                        elif state == 2:  # ELECT
                            self.logger.info("Trigger leader election...")
                            self.elect_leader()
                            self.logger.info("Leader election triggered successfully")

                        elif state == 3:  # EXECUTE
                            self.logger.info("Checking leader duties...")
                            was_leader = self.is_leader
                            self.check_and_perform_leader_duties()
                            if self.is_leader != was_leader:
                                self.logger.info("Node leadership status changed")
                                self.logger.info(f"Current role: {'Leader' if self.is_leader else 'Not leader'}")
                            self.logger.info("Checking leader duties complete")

                        elif state == 4:  # CONFIRM
                            self.logger.info("Processing assigned jobs...")
                            self.process_assigned_jobs()
                            self.logger.info("Job processing complete")

                        elif state == 5:  # DISPUTE
                            self.logger.info("Start incentive cycle...")
                            self.start_incentive_cycle()
                            self.logger.info("Incentive cycle complete")
                            epochs_processed += 1

                    except Exception as phase_error:
                        self.logger.error(f"Error in {current_phase} phase: {phase_error}")
                        self.logger.exception("Detailed traceback:")
                        # Continue to next iteration rather than crashing
                        if self.test_mode:
                            time.sleep(10)
                            # Process any last events
                            self._check_for_events()
                            raise
                        continue

                # Exit after first cycle for testing
                if self.test_mode and epochs_processed >= 1:
                    self.logger.info("Test cycle complete")
                    time.sleep(10)
                    # Process any last events
                    self._check_for_events()
                    break

                # Node can begin after first DISPUTE phase,
                # so that the cycle starts correctly from COMMIT
                if state == 5:
                    can_begin = True

                # Sleep until next phase, but check events frequently
                sleep_time = min(time_left, 2)  # Check events every 2 seconds
                time.sleep(sleep_time)

            except Exception as e:
                self.logger.error(f"Critical error in main loop: {e}")
                self.logger.exception("Detailed traceback:")

                # Log node state for debugging
                self.logger.error("=== Node State at Error ===")
                self.logger.error(f"Current phase: {state_names.get(state, 'Unknown')}")
                self.logger.error(f"Is leader: {self.is_leader}")
                self.logger.error(f"Has current secret: {bool(self.current_secret)}")
                self.logger.error(f"Has current commitment: {bool(self.current_commitment)}")
                self.logger.error("=========================")

                time.sleep(5)  # Brief pause before retrying


def initialize_lumino_node(config_path: str = None) -> LuminoNode:
    """Initialize a Lumino node from a config file"""
    # Get the absolute path to the project root and contracts directory
    current_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = current_dir  # Assuming node_client.py is in project root
    contracts_dir = os.path.join(project_root, "src")

    # Load configuration
    config = {
        'web3_provider': os.getenv('RPC_URL'),
        'private_key': os.getenv('NODE_PRIVATE_KEY'),
        'contract_addresses': {
            'LuminoToken': os.getenv('LUMINO_TOKEN_ADDRESS'),
            'AccessManager': os.getenv('ACCESS_MANAGER_ADDRESS'),
            'WhitelistManager': os.getenv('WHITELIST_MANAGER_ADDRESS'),
            'NodeManager': os.getenv('NODE_MANAGER_ADDRESS'),
            'IncentiveManager': os.getenv('INCENTIVE_MANAGER_ADDRESS'),
            'NodeEscrow': os.getenv('NODE_ESCROW_ADDRESS'),
            'LeaderManager': os.getenv('LEADER_MANAGER_ADDRESS'),
            'JobManager': os.getenv('JOB_MANAGER_ADDRESS'),
            'EpochManager': os.getenv('EPOCH_MANAGER_ADDRESS'),
            'JobEscrow': os.getenv('JOB_ESCROW_ADDRESS')
        },
        'contracts_dir': contracts_dir,
        'data_dir': os.path.join(project_root, os.getenv('NODE_DATA_DIR')),
        'test_mode': os.getenv('TEST_MODE', None)
    }
    config = LuminoConfig.from_file(config_path) if config_path else LuminoConfig(**config)

    # Initialize node
    node = LuminoNode(config)
    return node


if __name__ == "__main__":
    # Initialize node from config file
    node = initialize_lumino_node()
    node.register_node(compute_rating=int(os.getenv('COMPUTE_RATING')))

    # Run main loop
    node.run()
