// SPDX-Lisence-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockDSCMintFailed is Ownable, ERC20Burnable {
    error MintFailed_AmountCantBeZero();
    error MintFailed_BurnAmountCantBeLessThanBalance();
    error MintFailed_ZeroAddressNotAllowed();

    constructor() ERC20("mintFailed", "MF") {}

    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) {
            revert MintFailed_AmountCantBeZero();
        }
        if (amount > balanceOf(msg.sender)) {
            revert MintFailed_BurnAmountCantBeLessThanBalance();
        }

        super.burn(amount);
    }

    function mint(address account, uint256 amount) external onlyOwner returns (bool) {
        if (account == address(0)) {
            revert MintFailed_ZeroAddressNotAllowed();
        }
        if (amount <= 0) {
            revert MintFailed_AmountCantBeZero();
        }

        _mint(account, amount);

        return false;
    }
}
