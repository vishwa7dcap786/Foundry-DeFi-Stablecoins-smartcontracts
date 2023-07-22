// SPDX-Lisence-Identifier:MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

contract MockTransferFailed is Ownable, ERC20Burnable {
    error MockDSC_ZeroAmountNotAllowed();
    error MockDSC_BurnAmountExceeds();

    constructor() ERC20("MockDSC", "MockDSC") {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount <= 0) {
            revert MockDSC_ZeroAmountNotAllowed();
        }
        if (amount > balance) {
            revert MockDSC_BurnAmountExceeds();
        }

        super.burn(amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }
}
