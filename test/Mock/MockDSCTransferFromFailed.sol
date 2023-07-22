// SPDX-Lisence-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

contract MockDSCTransferFromFailed is ERC20Burnable, Ownable {
    error amount_MoreThanZero();
    error amount_ExceedsAccountBalance();

    constructor() ERC20("MOKT", "MOKT") {}

    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) {
            revert amount_MoreThanZero();
        }
        if (amount > balanceOf(msg.sender)) {
            revert amount_ExceedsAccountBalance();
        }

        super.burn(amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}
