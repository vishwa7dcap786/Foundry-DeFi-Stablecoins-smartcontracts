// SPDX-Lisence-Identifier:MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStablecoins} from "../../src/DecentralizedStablecoins.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin-contracts/mocks/ERC20Mock.sol";
import {MockDSCTransferFromFailed} from "../Mock/MockDSCTransferFromFailed.sol";
import {MockTransferFailed} from "../Mock/MockTransferFailed.sol";
import {MockDSCMintFailed} from "../Mock/MockDSCMintFailed.sol";
import {MockDSCDept} from "../Mock/MockDSCDept.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC Deployer;
    DSCEngine engine;
    DecentralizedStablecoins DSC;
    HelperConfig config;

    address ETHpriceFeedAddress;
    address BTCpriceFeedAddress;
    address WETH;
    address WBTC;
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public INITIAL_AMOUNT = 10 ether;
    uint256 public amountToMintDSC = 100 ether;

    address public USER = makeAddr("user");

    address public liquidator = makeAddr("liquidator");
    uint256 public COLLATERAL_AMOUNT_TO_COVER = 20 ether;

    function setUp() public {
        Deployer = new DeployDSC();

        (DSC, engine, config) = Deployer.run();
        (ETHpriceFeedAddress, BTCpriceFeedAddress, WETH, WBTC,) = config.activeNetworkConfig();

        ERC20Mock(WETH).mint(USER, INITIAL_AMOUNT);
        ERC20Mock(WBTC).mint(USER, INITIAL_AMOUNT);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddress;

    // Constructor Test
    function testRevertIfLengthIsNotSame() public {
        tokenAddresses.push(WETH);
        priceFeedAddress.push(ETHpriceFeedAddress);
        priceFeedAddress.push(BTCpriceFeedAddress);
        vm.expectRevert(DSCEngine.priceFeedsAddresslengthAndtokenAddresslengthMustBeInSameLength.selector);
        new DSCEngine(tokenAddresses,priceFeedAddress,address(DSC));
    }

    // Price Feeds Test
    function testGetUSDValues() public {
        uint256 ETHamount = 15e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = engine.getUSDValues(WETH, ETHamount);

        assertEq(actualUSD, expectedUSD);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 USDAmountInWei = 100 ether;
        uint256 expected = 0.05 ether;
        uint256 actual = engine.getTokenAmountFromUSD(WETH, USDAmountInWei);
        assertEq(actual, expected);
    }

    // depositeCollateral Test

    function testRevertUnallowedToken() public {
        uint256 amount = 10;
        ERC20Mock MockToken = new ERC20Mock("MOK","MOK",USER,COLLATERAL_AMOUNT);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.NotAllowedToken.selector);
        engine.depositCollateral(address(MockToken), amount);
        vm.stopPrank();
    }

    function testRevertTransferFromFailed() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockDSCTransferFromFailed Mockdsc = new MockDSCTransferFromFailed();
        tokenAddresses = [address(Mockdsc)];
        priceFeedAddress = [ETHpriceFeedAddress];

        vm.prank(owner);
        DSCEngine Mockdsce = new DSCEngine(tokenAddresses,priceFeedAddress,address(Mockdsc));

        vm.prank(owner);
        Mockdsc.mint(USER, COLLATERAL_AMOUNT);

        vm.prank(owner);
        Mockdsc.transferOwnership(address(Mockdsce));

        vm.startPrank(USER);
        ERC20Mock(address(Mockdsc)).approve(address(Mockdsce), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.transactionCollateral_failed.selector);
        Mockdsce.depositCollateral(address(Mockdsc), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testLessCollateralAmountReverts() public {
        uint256 amount = 0;
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.Amount_NeedsMoreThanZero.selector);
        engine.depositCollateral(WETH, amount);
        vm.stopPrank();
    }

    modifier depositeCollaterals() {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(WETH, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanDepositeCollateralWithoutMinting() public depositeCollaterals {
        uint256 balance = DSC.balanceOf(USER);
        assertEq(balance, 0);
    }

    function testCanDepositeCollateralAndGetAccountInfo() public depositeCollaterals {
        (uint256 totalCollateralAmount, uint256 totalDSCMinted) = engine.getAccountInfo(USER);
        uint256 expectedCollateralAmountInUSD = engine.getUSDValues(WETH, COLLATERAL_AMOUNT);
        assertEq(totalDSCMinted, 0);
        assertEq(totalCollateralAmount, expectedCollateralAmountInUSD);
    }

    function testRevertsIfMintedDSCBreaksHealthFactor() public {
        (, int256 prices,,,) = MockV3Aggregator(ETHpriceFeedAddress).latestRoundData();
        uint256 amountToMint =
            (COLLATERAL_AMOUNT * (uint256(prices) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        // uint256 expectedHealthFactor =
        //  engine.calculateHealthFactor(engine.getUSDValues(WETH, COLLATERAL_AMOUNT), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorIsBelowMin.selector);
        engine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMint);
        vm.stopPrank();
    }

    modifier depositeCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);

        engine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);
        vm.stopPrank();
        _;
    }

    function testCanDepositeAndMint() public depositeCollateralAndMintDSC {
        uint256 userBalance = DSC.balanceOf(USER);
        assertEq(userBalance, amountToMintDSC);
    }

    function testRevertIfMintFailed() public {
        address owner = msg.sender;
        MockDSCMintFailed MockDSC = new MockDSCMintFailed();
        tokenAddresses = [WETH];
        priceFeedAddress = [ETHpriceFeedAddress];
        address DSCaddress = address(MockDSC);
        vm.prank(owner);
        DSCEngine MockEngine = new DSCEngine(tokenAddresses,priceFeedAddress,DSCaddress);

        MockDSC.transferOwnership(address(MockEngine));

        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(MockEngine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine_MintingFailed.selector);
        MockEngine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);
        vm.stopPrank();
    }

    function testRevertIfMintAmountIsZero() public {
        uint256 amountToMint = 0;
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);

        vm.expectRevert(DecentralizedStablecoins.DecentralizedStablecoins_MustBeMoreThanZero.selector);
        engine._mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintedAmountBreaksHealthFactor() public {
        (, int256 prices,,,) = MockV3Aggregator(ETHpriceFeedAddress).latestRoundData();
        amountToMintDSC =
            (COLLATERAL_AMOUNT * (uint256(prices) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();

        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);

        engine.depositCollateral(WETH, COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorIsBelowMin.selector);
        engine.mintDSC(amountToMintDSC);
    }

    function testCanMintDSC() public depositeCollaterals {
        vm.startPrank(USER);

        engine.mintDSC(amountToMintDSC);
        uint256 balance = DSC.balanceOf(USER);
        assertEq(balance, amountToMintDSC);
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);
        vm.expectRevert(DSCEngine.Amount_NeedsMoreThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDSC(1);
    }

    function testCanBurnDsc() public depositeCollateralAndMintDSC {
        uint256 expectedBalance = 20 ether;

        vm.startPrank(USER);
        DSC.approve(address(engine), amountToMintDSC);

        // uint256 revertif = engine._revertifHealthFactorisBroken(USER).userHealthFactor;

        engine.burnDSC(80 ether);
        //(uint256 col, uint256 min) = engine.getAccountInfo(USER);
        // console.log(col, min);
        // uint256 health = engine.calculateHealthFactor(col, min);
        // console.log(health);

        vm.stopPrank();

        uint256 userBalance = DSC.balanceOf(USER);
        assertEq(userBalance, expectedBalance);
    }

    function testTest() public {
        uint256 a = 0;
        uint256 b = 0;
        assertEq(a, b);
    }

    function testRevertsRedeemTransferFailed() public {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockTransferFailed MockDSC = new MockTransferFailed();
        tokenAddresses = [address(MockDSC)];
        priceFeedAddress = [ETHpriceFeedAddress];
        address DSCOINS = address(MockDSC);

        DSCEngine MockEngine = new DSCEngine(tokenAddresses,priceFeedAddress,DSCOINS);

        MockDSC.mint(USER, COLLATERAL_AMOUNT);

        MockDSC.transferOwnership(address(MockEngine));

        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(address(MockDSC)).approve(address(MockEngine), COLLATERAL_AMOUNT);

        MockEngine.depositCollateral(address(MockDSC), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.redeemCollateral_failed.selector);
        MockEngine.redeemCollateral(address(MockDSC), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public depositeCollaterals {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.Amount_NeedsMoreThanZero.selector);
        engine.redeemCollateral(WETH, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositeCollateralAndMintDSC {
        vm.startPrank(USER);
        engine.redeemCollateral(WETH, 8 ether);
        uint256 userBalance = engine.getCollateralBalanceOfUser(USER, WETH);
        assertEq(userBalance, 2 ether);
        vm.stopPrank();
    }

    function testMustRedeemMoreThanZero() public depositeCollateralAndMintDSC {
        vm.startPrank(USER);
        ERC20Mock(address(DSC)).approve(address(engine), amountToMintDSC);
        vm.expectRevert(DSCEngine.Amount_NeedsMoreThanZero.selector);
        engine.redeemCollateralAndBurnDSC(WETH, 0, amountToMintDSC);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public depositeCollateralAndMintDSC {
        vm.startPrank(USER);
        ERC20Mock(address(DSC)).approve(address(engine), amountToMintDSC);
        engine.redeemCollateralAndBurnDSC(WETH, 2 ether, 20 ether);

        vm.stopPrank();
        uint256 userBalance = engine.getCollateralBalanceOfUser(USER, WETH);
        assertEq(userBalance, 8 ether);
    }

    function testHealthFactorReports() public depositeCollateralAndMintDSC {
        uint256 expectedHealthFactor = 100 ether;
        uint256 actualHealthFactor = engine.getHealthFactor(USER);

        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositeCollateralAndMintDSC {
        int256 ethPrice = 18e8;
        MockV3Aggregator(ETHpriceFeedAddress).updateAnswer(ethPrice);

        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assert(actualHealthFactor == 0.9 ether);
    }

    function testMustImproveHealthFactor() public {
        MockDSCDept MockDSC = new MockDSCDept(ETHpriceFeedAddress);
        priceFeedAddress = [ETHpriceFeedAddress];
        tokenAddresses = [WETH];
        address DSCAddress = address(MockDSC);
        DSCEngine MockEngine = new DSCEngine(tokenAddresses,priceFeedAddress,DSCAddress);

        MockDSC.transferOwnership(address(MockEngine));

        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(MockEngine), COLLATERAL_AMOUNT);

        MockEngine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);
        vm.stopPrank();

        COLLATERAL_AMOUNT_TO_COVER = 1 ether;
        ERC20Mock(WETH).mint(liquidator, COLLATERAL_AMOUNT_TO_COVER);

        vm.startPrank(liquidator);
        ERC20Mock(WETH).approve(address(MockEngine), COLLATERAL_AMOUNT_TO_COVER);
        MockEngine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT_TO_COVER, amountToMintDSC);
        uint256 deptToCover = 10 ether;
        MockDSC.approve(address(MockEngine), deptToCover);

        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ETHpriceFeedAddress).updateAnswer(ethUsdUpdatedPrice);

        (uint256 USERINFO, uint256 USERINFO2) = MockEngine.getAccountInfo(USER);
        (uint256 LIQINFO, uint256 LIQINFO2) = MockEngine.getAccountInfo(liquidator);
        console.log(USERINFO, USERINFO2);
        console.log(LIQINFO, LIQINFO2);

        vm.expectRevert(DSCEngine.healthFactorIsNotImproved.selector);
        MockEngine.liquidate(WETH, USER, deptToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);

        engine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);
        vm.stopPrank();

        ERC20Mock(WETH).mint(liquidator, 100 ether);

        vm.startPrank(liquidator);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);

        engine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);
        vm.expectRevert(DSCEngine.DSCEngine_healthFactorOK.selector);
        engine.liquidate(WETH, USER, 10 ether);

        vm.stopPrank();
    }

    modifier liquidate() {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositeColateralAndMintDSC(WETH, COLLATERAL_AMOUNT, amountToMintDSC);
        vm.stopPrank();
        int256 ETHpriceFeeds = 18e8;
        MockV3Aggregator(ETHpriceFeedAddress).updateAnswer(ETHpriceFeeds);
        uint256 collateralToCover = 20 ether;

        ERC20Mock(WETH).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(WETH).approve(address(engine), collateralToCover);
        engine.depositeColateralAndMintDSC(WETH, collateralToCover, amountToMintDSC);
        DSC.approve(address(engine), amountToMintDSC);
        engine.liquidate(WETH, USER, amountToMintDSC);
        vm.stopPrank();

        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidate {
        uint256 liquidatorWETHBalance = ERC20Mock(WETH).balanceOf(liquidator);
        uint256 expectedWETH = engine.getTokenAmountFromUSD(WETH, amountToMintDSC)
            + (engine.getTokenAmountFromUSD(WETH, amountToMintDSC) / engine.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWETHBalance, hardCodedExpected);
        assertEq(liquidatorWETHBalance, expectedWETH);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidate {
        (, uint256 liquidatorDscMinted) = engine.getAccountInfo(liquidator);
        assertEq(liquidatorDscMinted, amountToMintDSC);
    }

    function testUserHasNoMoreDebt() public liquidate {
        (, uint256 userDscMinted) = engine.getAccountInfo(USER);
        assertEq(userDscMinted, 0);
    }
    //d

    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = engine.getCollateralTokenPriceFeed(WETH);
        assertEq(priceFeed, ETHpriceFeedAddress);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[0], WETH);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = engine.getMinHealthFactor();
        assertEq(minHealthFactor, 1e18);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = engine.getLiquidationThreshold();
        assertEq(liquidationThreshold, 50);
    }

    function testGetAccountCollateralValueFromInformation() public depositeCollaterals {
        (uint256 collateralValue,) = engine.getAccountInfo(USER);
        uint256 expectedCollateralValue = engine.getUSDValues(WETH, COLLATERAL_AMOUNT);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(WETH, COLLATERAL_AMOUNT);
        vm.stopPrank();
        uint256 collateralBalance = engine.getCollateralBalanceOfUser(USER, WETH);
        assertEq(collateralBalance, COLLATERAL_AMOUNT);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(WETH, COLLATERAL_AMOUNT);
        vm.stopPrank();
        uint256 collateralValue = engine.getCollateralValueInfo(USER);
        uint256 expectedCollateralValue = engine.getUSDValues(WETH, COLLATERAL_AMOUNT);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public {
        address dscAddress = engine.getDsc();
        assertEq(dscAddress, address(DSC));
    }

    function testGetPricision() public {
        uint256 PRICISION = 1e18;
        uint256 getPricision = engine.getPrecision();
        assertEq(getPricision, PRICISION);
    }
}
