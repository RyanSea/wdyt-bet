// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ERC20 } from "solady/tokens/ERC20.sol";

contract MockUSDB is ERC20 { 
    bool constant public IS_SCRIPT = true;
    
    function name() public pure override returns (string memory) {
        return "USDB";
    }

    function symbol() public pure override returns (string memory) {
        return "USDB Token";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address, uint256 amount) internal override {
        _approve(from, msg.sender, amount);
    }
}