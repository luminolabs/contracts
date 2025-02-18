// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract LuminoToken is ERC20, Ownable {
    uint8 private constant DECIMALS = 18;
    uint256 private constant INITIAL_SUPPLY = 100_000_000; // 100 million tokens

    constructor() ERC20("Lumino", "LUM") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY * (1000 ** decimals()));
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