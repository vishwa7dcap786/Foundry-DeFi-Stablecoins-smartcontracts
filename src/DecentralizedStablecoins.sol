// SPDX-Lisence-Identifier:MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
/*
* @title Decentralized stable coins
* @author vishwa
* Relative stability: pegged or anchored to USD
* collateral: Exogenous (ETH/BTC)
* Minting: Algorithmic
* 
* This contract is meant to be governed by DSCEngine. This contract is just the 
* implementation of ERC20
*
*/

contract DecentralizedStablecoins is ERC20Burnable, Ownable {
    error DecentralizedStablecoins_MustBeMoreThanZero();
    error DecentralizedStablecoins_BurnAmountExceedsBalance();
    error DecentralizedStablecoins_MintToTheZeroAddress();

    constructor() ERC20("DecentralizedStablecoins", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStablecoins_MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralizedStablecoins_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address account, uint256 _amount) external onlyOwner returns (bool) {
        if (account == address(0)) {
            revert DecentralizedStablecoins_MintToTheZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStablecoins_MustBeMoreThanZero();
        }
        _mint(account, _amount);
        return true;
    }
}
