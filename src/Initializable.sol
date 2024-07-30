// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Initializable
 * @dev A base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts can't have constructors, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. This contract provides modifiers to protect this
 * initializer function from being invoked multiple times.
 *
 * Modified from OpenZeppelin's Initializable contract.
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /**
     * @dev Modifier to check if the contract has been initialized.
     */
    modifier initialized() {
        require(_initialized, "Initializable: contract is not initialized");
        _;
    }

    /**
     * @dev Returns true if the contract is initialized.
     */
    function isInitialized() public view returns (bool) {
        return _initialized;
    }
}