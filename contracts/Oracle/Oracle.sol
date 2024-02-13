// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/AaveOracle/AaveOracle.sol";
import "../lib/Lyra/BlackScholes.sol";
import "../lib/ABDKMath64x64.sol";
import "../interfaces/IOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


/**
 * @title Oracle
 * @dev Built from AaveOracle. Includes additional oracle functionalities: risk free rate and volatility
 * Contract to get asset prices, manage price sources and update the fallback oracle
 * - Use of Chainlink Aggregators as first source of price
 * - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a fallback oracle
 * - Volatility is built from successive oracle recordings, may or may not be accurate
 */  
contract Oracle is AaveOracle, IOracle, Ownable {
  int256 private _riskFreeRate;
  uint16 private _ivMultiplierX2 = 135;
  
  mapping(address => mapping (uint => uint256)) private _assetDailyPrice;
  mapping(address => mapping (uint => uint256)) private _assetDailyVolatility;
  mapping(address => mapping (uint => uint8)) private _assetDailyVolRealLength;
  
  uint8 private constant VOL_LENGTH_IN_DAYS = 10;

  /**
   * @notice Constructor
   * @param assets The addresses of the assets
   * @param sources The address of the source of each asset
   * @param fallbackOracle The address of the fallback oracle to use if the data of an
   *        aggregator is not consistent
   * @param baseCurrency The base currency used for the price quotes. If USD is used, base currency is 0x0
   * @param baseCurrencyUnit The unit of the base currency
   */
  constructor(
    address[] memory assets,
    address[] memory sources,
    address fallbackOracle,
    address baseCurrency,
    uint256 baseCurrencyUnit,
    int256 riskFreeRate
  ) 
    AaveOracle(IPoolAddressesProvider(address(0x0)), assets, sources, fallbackOracle, baseCurrency, baseCurrencyUnit)
  {
    _riskFreeRate = riskFreeRate;
  }
  
  
  /// @notice Used for initializing the oracle as an upgradeable proxy
  function initializer(
    address[] memory assets,
    address[] memory sources,
    address baseCurrency,
    uint256 baseCurrencyUnit,
    int256 riskFreeRate
  ) public {
    require(owner() == address(0), "Already Init");
    _transferOwnership(msg.sender);
    _setAssetsSources(assets, sources);
    BASE_CURRENCY = baseCurrency;
    BASE_CURRENCY_UNIT = baseCurrencyUnit;
    emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    _riskFreeRate = riskFreeRate;
  }
  
  
    /// @inheritdoc IAaveOracle
  function setAssetSources(address[] calldata assets, address[] calldata sources) external override(AaveOracle, IAaveOracle) onlyOwner {
    _setAssetsSources(assets, sources);
  }

  /// @inheritdoc IAaveOracle
  function setFallbackOracle(address fallbackOracle) external override(AaveOracle, IAaveOracle) onlyOwner {
    _setFallbackOracle(fallbackOracle);
  }


  /// @inheritdoc IOracle
  function getRiskFreeRate() public view returns (int256){
    return _riskFreeRate;
  }  
  
  /// @inheritdoc IOracle
  function setRiskFreeRate(int256 riskFreeRate) external onlyOwner {
    _riskFreeRate = riskFreeRate;
    emit RiskFreeRateUpdated(riskFreeRate);
  }
  
  function getIVMultiplier() public view returns (uint16){
    return _ivMultiplierX2;
  }
  
  /// @notice Set the multiplier form HV to IV
  function setIVMultiplier(uint16 ivMultiplierX2) external onlyOwner {
    _ivMultiplierX2 = ivMultiplierX2;
    emit IVMultiplierUpdated(ivMultiplierX2);
  }


  /// @inheritdoc IOracle
  function getAssetPriceAtDay(address asset, uint thatDay) external view override returns (uint256) {
    return _assetDailyPrice[asset][thatDay];
  }

  
  /// @inheritdoc IOracle
  /// @dev Calculate volatility on days with recorded prices, missing days use last valid data
  function getAssetVolatility(address asset, uint8 length) public view returns (uint224 volatility){
    (volatility, ) = _volatility(asset, length);
  }
  
  /// @notice Computes asset volatility
  /// @return volatility Volatility X8, eg 5e7 is 0.5 = 50% 
  /// @return realLength Actual amount of days with data, useful to average down on new pairs
  function _volatility(address asset, uint8 length) public view returns (uint224 volatility, uint8 realLength){
    if (length < 2) return (0, 0);
    int128[] memory logReturns = new int128[](length);
    uint today = block.timestamp / 86400;
    int128 mean;
    uint lastPrice = _assetDailyPrice[asset][today - length];
    // Walk forward calculating the log returns and the mean
    for (uint i = 1; i <= length; i++){      
      uint price = _assetDailyPrice[asset][today - length + i];
      if (lastPrice > 0 && price > 0){
        int128 dailyRatio = ABDKMath64x64.divu(price, lastPrice);
        logReturns[i-1] = ABDKMath64x64.ln(dailyRatio);
        mean = ABDKMath64x64.add(mean, logReturns[i-1]);
        realLength++;
      }
      lastPrice = price;
    }
    mean = ABDKMath64x64.div(mean, ABDKMath64x64.fromUInt(length));
    int128 sumDev;
    // compute variance
    for (uint256 i = 0; i < length; i++){
      int128 diff = ABDKMath64x64.sub(logReturns[i], mean);
      sumDev += ABDKMath64x64.mul(diff, diff);
    }
    
    int128 varSquared = ABDKMath64x64.div(sumDev, ABDKMath64x64.fromUInt(length-1));
    int128 vol = ABDKMath64x64.sqrt(varSquared);
    // annualize over 365 trading days
    int128 volAnnualized = ABDKMath64x64.mul(vol, ABDKMath64x64.sqrt(ABDKMath64x64.fromUInt(365)));
    // convert to X8
    int128 volX8 = ABDKMath64x64.mul(volAnnualized, ABDKMath64x64.fromUInt(1e8));
    uint uVolX8 = ABDKMath64x64.toUInt(volX8);
    volatility = uint224(uVolX8);
  }
  
  
  /// @inheritdoc IOracle
  function snapshotDailyAssetsPrices(address[] calldata assets) external {
    uint today =  block.timestamp / 86400;
    for (uint256 i = 0; i < assets.length; i++) {
      address asset = assets[i];
      uint price = getAssetPrice(asset);
      if (price > 0 && _assetDailyPrice[asset][today] == 0) {
        _assetDailyPrice[asset][today] = price;
        (uint vol, uint8 realLength) = _volatility(asset, VOL_LENGTH_IN_DAYS);
        _assetDailyVolatility[asset][today] = vol;
        _assetDailyVolRealLength[asset][today] = realLength;
      }
    }
  }


  /// @notice Return the price of an option adjusted for current OI, in quoteToken amount
  function getOptionPrice(bool isCall, address baseToken, address quoteToken, uint strike, uint timeToExpirySec, uint utilizationRate) 
    public view returns (uint optionPrice) 
  {
    if (utilizationRate > 100) utilizationRate = 100;
    uint volatility = getAdjustedVolatility(baseToken, utilizationRate);
    // values used by BlackScholes library are e18, multiply by 1e10 for precision and divide back afterwards
    (uint callPrice, uint putPrice) =  getOptionPrice(isCall, baseToken, quoteToken, strike, timeToExpirySec, volatility, utilizationRate);
    optionPrice = (isCall ? callPrice : putPrice) / 1e10;
    if (optionPrice == 0) optionPrice = 1e6; // min option price $0.01
  }
  
  
  /// @notice Get the adjusted volatility based on current HV snapshot and IV bump
  function getAdjustedVolatility(address baseToken, uint utilizationRate) public view returns (uint volatility) {
    uint today =  block.timestamp / 86400;
    volatility = _assetDailyVolatility[baseToken][today];
    uint8 realLength = _assetDailyVolRealLength[baseToken][today];
    if (volatility == 0) (volatility, realLength) = _volatility(baseToken, VOL_LENGTH_IN_DAYS);
    // Base volatility for pairs with missing data: 400% (e.g, new Uniswap pair using TWAP price)
    if (realLength < 4) volatility = (uint(VOL_LENGTH_IN_DAYS - realLength) * 4e8 + uint(realLength) * volatility) / VOL_LENGTH_IN_DAYS;
    // IV > RV usually for options, so mark up volatility for option pricing
    volatility = volatility * _ivMultiplierX2 / 100;
    // Use the utilization rate to boost IV up linearly, add up to 30% IV @ 100% utilization rate
    volatility = volatility * (100 + utilizationRate / 3) / 100;
  }
  
  
  /// @notice Return the price of an option adjusted for current OI, in quoteToken amount
  function getOptionPrice(bool isCall, address baseToken, address quoteToken, uint strike, uint timeToExpirySec, uint volatility, uint utilizationRate)
    public view returns (uint callPrice, uint putPrice) 
  {
    uint priceX8 = getAssetPrice(baseToken) * 1e8 / getAssetPrice(quoteToken);
    // values used by BlackScholes library are e18, multiply by 1e10 for precision and divide back afterwards
    (callPrice, putPrice) =  BlackScholes.optionPrices(BlackScholes.BlackScholesInputs({
        timeToExpirySec: timeToExpirySec ,
        volatilityDecimal: volatility * 1e10,
        spotDecimal: priceX8 * 1e10, // DecimalMath uses 18 decimals while oracle price uses 8
        strikePriceDecimal: strike * 1e10,
        rateDecimal: _riskFreeRate * 1e10
      }));
  }
  
}
