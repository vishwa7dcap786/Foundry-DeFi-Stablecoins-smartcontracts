// SPDX-Lisence-Identifier:MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStablecoins} from "../src/DecentralizedStablecoins.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] private tokenAddress;
    address[] private priceFeedAddress;

    function run() external returns (DecentralizedStablecoins, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address WETHpriceFeedAddress,
            address WBTCpriceFeedAddress,
            address WETHTokenaddress,
            address WBTCTokenaddress,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        tokenAddress = [WETHTokenaddress, WBTCTokenaddress];
        priceFeedAddress = [WETHpriceFeedAddress, WBTCpriceFeedAddress];

        vm.startBroadcast(deployerKey);
        DecentralizedStablecoins DSC = new DecentralizedStablecoins();
        DSCEngine engine = new DSCEngine(tokenAddress,priceFeedAddress,address(DSC));
        DSC.transferOwnership(address(engine));

        vm.stopBroadcast();
        return (DSC, engine, helperConfig);
    }
}
