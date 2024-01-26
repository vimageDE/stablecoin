// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title DSCEngine
/// @author Mark Gretzke
// The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg.
/// This stablecoin hast the propperties:
/// - Exogenous Collateral
/// - Dollar Pegged
/// - Algoritmically Stable
/// It is similar to DAI if it had no governance, no fees and was only backed by WETH and WBTC
/// Our DSC system should always be "overcollateralized. At no point, should the value of
/// all collateral <= $ backed value of all the DSC.
/// @notice this contract ist the coreof the DSC System. It handles all the logic for
/// minting and redeeming DSC, as well as the depositing & withdrawing collateral.
/// @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
contract DSCEngine is ReentrancyGuard{
    ///////////////
    //  Errors   //
    ///////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    ////////////////////////
    //  State Variables   //
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    DecentralizedStableCoin private immutable i_dsc;
    
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    ///////////////
    //  Events   //
    ///////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    ///////////////
    // Modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    function depositCollateralAndMintDsc() external {}
    /// @notice follows CEI
    /// @param tokenCollateralAddress The address of the token to deposit as collateral
    /// @param amountCollateral The amount of collateral to deposit
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }
    function redeeCollateralForDsc() external {}
    function redeemCollateral() external {}
    /// @param amountDscToMint The amount of edecentralized stablecoin to mint
    /// @notice they must have more collateral value then the minimum threshold
    function mintDSC(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;

    }
    function burnDsc() external {}
    function liquidate() external {}
    ////////////////////////
    // Private & Internal //
    ////////////////////////

    function _getAccountInformation(address user) private view returns(uint256 totalDSCMinted, uint256 collateralValueInUsd){
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /// returns how close to liquidation a user is
    /// If a user goes below 1, then they can get liquidated
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    }
    function _revertIfHealthFactorIsBroken(address user) internal view{

    }
    ////////////////////////
    // View Functions     //
    ////////////////////////
    function getAccountCollateralValueInUsd(address user) public view returns(uint256 totalCollateralValueInUsd){
        for(uint256 i=0; i<s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getHealthFactor() external view {}
}
