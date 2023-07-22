// SPDX-Lisence-Identifier:MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract MockDSCDept is ERC20Burnable, Ownable {
    error MockDSC_ZeroAmountNotAllowed();
    error MockDSC_BurnAmountExceeds();
    error MockDSC_ZeroAddressNotAllowed();

    address mockAggregator;

    constructor(address _mockAggregator) ERC20("MockDSC", "MockDSC") {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) {
            revert MockDSC_ZeroAmountNotAllowed();
        }
        if (amount > balanceOf(msg.sender)) {
            revert MockDSC_BurnAmountExceeds();
        }

        super.burn(amount);
    }

    function mint(address account, uint256 amount) public onlyOwner returns (bool) {
        if (amount <= 0) {
            revert MockDSC_ZeroAmountNotAllowed();
        }
        if (account == address(0)) {
            revert MockDSC_ZeroAddressNotAllowed();
        }

        _mint(account, amount);
        return true;
    }
}
