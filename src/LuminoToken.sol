// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";


contract LuminoToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    uint8 private constant DECIMALS = 18;
    uint256 private constant INITIAL_SUPPLY = 100_000_000; // 100 million tokens

     function initialize() external initializer {
        __ERC20_init("Lumino", "LUM");
        __Ownable_init(msg.sender);
        _mint(msg.sender, INITIAL_SUPPLY * (10 ** decimals()));
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}