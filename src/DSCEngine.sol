// SPDX-Lisence-Identifier:MIT

pragma solidity ^0.8.20;

import {DecentralizedStablecoins} from "./DecentralizedStablecoins.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";
import {OracleLib, AggregatorV3Interface} from "./libraries/oracleLib.sol";

/*
 * @title Decentralized stable coins
 * @author vishwa
 *
 * Relative stability: pegged or anchored to USD
 * collateral: Exogenous (ETH/BTC)
 * Minting: Algorithmic
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 *
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    //Errors

    error Amount_NeedsMoreThanZero();
    error priceFeedsAddresslengthAndtokenAddresslengthMustBeInSameLength();
    error NotAllowedToken();
    error transactionCollateral_failed();
    error DSCEngine_HealthFactorIsBelowMin();
    error healthFactorIsNotImproved();
    error DSCEngine_healthFactorOK();
    error DSCEngine_MintingFailed();
    error redeemCollateral_failed();
    error burnDSC_failed();
    error DSCtokenMinted_IsZero();

    //Stable Variables

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    DecentralizedStablecoins private immutable i_dsc;

    address[] private s_collateralTokens;
    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;

    //Events

    event collateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed collateralAmount
    );
    event collateralRedeemed(address indexed redeemedFrom, uint256 indexed amountCollateral, address from, address to);

    //Modifiers

    modifier moreThanZeroAmount(uint256 amount) {
        if (amount <= 0) {
            revert Amount_NeedsMoreThanZero();
        }
        _;
    }

    modifier isallowedtoken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert NotAllowedToken();
        }
        _;
    }

    //Functions

    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddress, address DSCaddress) {
        if (tokenAddresses.length != priceFeedsAddress.length) {
            revert priceFeedsAddresslengthAndtokenAddresslengthMustBeInSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStablecoins(DSCaddress);
    }

    //External Functions

    function depositeColateralAndMintDSC(
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 amountofDSCToMint
    ) external {
        _depositCollateral(collateralTokenAddress, collateralAmount);
        _mintDSC(amountofDSCToMint);
    }

    function depositCollateral(address collateralTokenAddress, uint256 collateralAmount)
        external
        moreThanZeroAmount(collateralAmount)
        isallowedtoken(collateralTokenAddress)
        nonReentrant
    {
        _depositCollateral(collateralTokenAddress, collateralAmount);
    }

    function mintDSC(uint256 amountofDSCToMint) external moreThanZeroAmount(amountofDSCToMint) nonReentrant {
        _mintDSC(amountofDSCToMint);
    }

    function redeemCollateralAndBurnDSC(
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 amountofDSCToBurn
    ) external moreThanZeroAmount(collateralAmount) isallowedtoken(collateralTokenAddress) nonReentrant {
        _burnDSC(amountofDSCToBurn, msg.sender, msg.sender);
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertifHealthFactorisBroken(msg.sender);
    }

    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount)
        external
        moreThanZeroAmount(collateralAmount)
        isallowedtoken(collateralTokenAddress)
        nonReentrant
    {
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertifHealthFactorisBroken(msg.sender);
    }

    function burnDSC(uint256 amountofDSCToBurn) external moreThanZeroAmount(amountofDSCToBurn) nonReentrant {
        _burnDSC(amountofDSCToBurn, msg.sender, msg.sender);
        (uint256 col, uint256 min) = _getAccountInfo(msg.sender);
        console.log(col, min);
        // console.log(_healthFactor(msg.sender));
        _revertifHealthFactorisBroken(msg.sender); //this line will never hit!
    }

    function liquidate(address collateralTokenAddress, address user, uint256 debtToCover) external {
        uint256 startingHealthFactor = _healthFactor(user);
        console.log(startingHealthFactor);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine_healthFactorOK();
        }

        uint256 tokenAmountToDebt = getTokenAmountFromUSD(collateralTokenAddress, debtToCover);
        uint256 collateralBonus = (tokenAmountToDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        console.log(tokenAmountToDebt + collateralBonus);
        _redeemCollateral(collateralTokenAddress, tokenAmountToDebt + collateralBonus, user, msg.sender);
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        console.log(endingHealthFactor);
        if (endingHealthFactor <= MIN_HEALTH_FACTOR) {
            revert healthFactorIsNotImproved();
        }

        _revertifHealthFactorisBroken(msg.sender);
    }

    // Public Function

    function _depositCollateral(address collateralTokenAddress, uint256 collateralAmount) public {
        s_collateralDeposited[msg.sender][collateralTokenAddress] += collateralAmount;
        emit collateralDeposited(msg.sender, collateralTokenAddress, collateralAmount);

        bool success = IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert transactionCollateral_failed();
        }
    }

    function _mintDSC(uint256 amountofDSCToMint) public {
        s_DSCMinted[msg.sender] += amountofDSCToMint;
        _revertifHealthFactorisBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountofDSCToMint);
        if (!minted) {
            revert DSCEngine_MintingFailed();
        }
    }

    // Private Function

    function _redeemCollateral(address collateralTokenAddress, uint256 collateralAmount, address from, address to)
        public
    {
        s_collateralDeposited[from][collateralTokenAddress] -= collateralAmount;
        emit collateralRedeemed(from, collateralAmount, from, to);

        bool transfered = IERC20(collateralTokenAddress).transfer(to, collateralAmount);
        if (!transfered) {
            revert redeemCollateral_failed();
        }
    }

    function _burnDSC(uint256 amountofDSCToBurn, address onBehalfOf, address burnDSCFrom) public {
        s_DSCMinted[onBehalfOf] -= amountofDSCToBurn;

        bool success = i_dsc.transferFrom(burnDSCFrom, address(this), amountofDSCToBurn);
        if (!success) {
            revert burnDSC_failed();
        }
        i_dsc.burn(amountofDSCToBurn);
    }

    // Private && internal View && Pure Functions

    function _getUSDValues(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeeds = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 prices,,,) = OracleLib.staleCheckLatestRoundData(priceFeeds);

        return ((uint256(prices) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _getAccountInfo(address user)
        private
        view
        returns (uint256 totalCollateralValueinUSD, uint256 DSCtokenMinted)
    {
        totalCollateralValueinUSD = getCollateralValueInfo(user);
        DSCtokenMinted = s_DSCMinted[user];
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalCollateralValueinUSD, uint256 DSCtokenMinted) = _getAccountInfo(user);

        return _calculateHealthFactor(totalCollateralValueinUSD, DSCtokenMinted);

        // collateralAmountValueInUSD pricefeed
    }

    function _calculateHealthFactor(uint256 totalCollateralValueinUSD, uint256 DSCtokenMinted)
        internal
        pure
        returns (uint256)
    {
        if (DSCtokenMinted == 0) return type(uint256).max;

        uint256 CollateralAdjustedForThreshold =
            (totalCollateralValueinUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (CollateralAdjustedForThreshold * PRECISION) / DSCtokenMinted;
    }

    function _revertifHealthFactorisBroken(address user) public view {
        uint256 userHealthFactor = _healthFactor(user);
        console.log(userHealthFactor < MIN_HEALTH_FACTOR);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_HealthFactorIsBelowMin();
        }
        //check whether it is overcollateralized or not
        //revert if not good in health factor
    }

    // External && Public View && Pure Functions

    function calculateHealthFactor(uint256 totalCollateralValueinUSD, uint256 DSCtokenMinted)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalCollateralValueinUSD, DSCtokenMinted);
    }

    function getAccountInfo(address user)
        external
        view
        returns (uint256 totalCollateralValueinUSD, uint256 DSCtokenMinted)
    {
        return _getAccountInfo(user);
    }

    function getUSDValues(address token, uint256 amount) external view returns (uint256) {
        return _getUSDValues(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getTokenAmountFromUSD(address token, uint256 amountUSDinWei) public view returns (uint256) {
        AggregatorV3Interface priceFeeds = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 prices,,,) = OracleLib.staleCheckLatestRoundData(priceFeeds);
        console.log((amountUSDinWei * PRECISION) / (uint256(prices) * ADDITIONAL_FEED_PRECISION));
        //10e18*1e18/prices*1e10
        return (amountUSDinWei * PRECISION) / (uint256(prices) * ADDITIONAL_FEED_PRECISION);
    }

    function getCollateralValueInfo(address user) public view returns (uint256 totalCollateralValueinUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueinUSD += _getUSDValues(token, amount);
        }

        return totalCollateralValueinUSD;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
