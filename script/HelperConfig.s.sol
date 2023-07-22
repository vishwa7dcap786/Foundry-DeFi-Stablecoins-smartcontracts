// SPDX-Lisence-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin-contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address WETHpriceFeedAddress;
        address WBTCpriceFeedAddress;
        address WETHTokenaddress;
        address WBTCTokenaddress;
        uint256 deployerKey;
    }

    uint8 _decimals = 8;
    int256 _ETHinitialAnswer = 2000e8;
    int256 _BTCinitialAnswer = 1000e8;

    uint256 private DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getorcreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory SepoliaNetworkConfig) {
        SepoliaNetworkConfig = NetworkConfig({
            WETHpriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            WBTCpriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            WETHTokenaddress: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            WBTCTokenaddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getorcreateAnvilEthConfig() public returns (NetworkConfig memory AnvilNetworkConfig) {
        if (activeNetworkConfig.WETHpriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUSDPrice = new MockV3Aggregator(_decimals,_ETHinitialAnswer);
        ERC20Mock WETHMock = new ERC20Mock("WETH","WRTH",msg.sender,1000e8);

        MockV3Aggregator ethBTCPrice = new MockV3Aggregator(_decimals,_BTCinitialAnswer);
        ERC20Mock WBTCMock = new ERC20Mock("WBTC","WBTC",msg.sender,1000e8);

        vm.stopBroadcast();
        AnvilNetworkConfig = NetworkConfig({
            WETHpriceFeedAddress: address(ethUSDPrice),
            WBTCpriceFeedAddress: address(ethBTCPrice),
            WETHTokenaddress: address(WETHMock),
            WBTCTokenaddress: address(WBTCMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
