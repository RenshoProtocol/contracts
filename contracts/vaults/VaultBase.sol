// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../PositionManager/PositionManager.sol";
import "../interfaces/IVault.sol";
import "./VaultConfigurator.sol";
import "../Commons.sol";
import "./FeeStreamer.sol";


contract VaultBase is Commons, VaultConfigurator, ERC20("", ""), ReentrancyGuard, IVault, FeeStreamer {
  using SafeERC20 for ERC20;
  
  event Deposit(address indexed sender, address indexed token, uint amount, uint liquidity);
  event Withdraw(address indexed sender, address indexed token, uint amount, uint liquidity);
  event Borrowed(address indexed tickerAddress, uint tickerAmount);
  event Repaid(address indexed tickerAddress, uint tickerAmount);

  /// @notice Whitelist of position managers
  PositionManager public positionManager;
  
  /// @notice Withdrawals intents
  mapping(address => uint) public withdrawalIntents;
  uint public totalIntents;
  
  /// CONSTANTS 
  uint256 private constant Q96 = 0x1000000000000000000000000;
  uint256 private constant UINT256MAX = type(uint256).max;
  
  
  modifier onlyOPM() {
    require(address(positionManager) == msg.sender, "GEV: Unallowed PM");
    _;
  }
  
  /// @notice Initialize the vault, use after spawning a new proxy. Caller should be an instance of Controller
  function initProxy(address _baseToken, address _quoteToken, address _positionManager, address weth, address _oracle) public virtual {
    require(address(controller) == address(0), "GEV: Already Init");
    require(_baseToken != address(0) && _quoteToken != address(0) && _oracle != address(0), "GEV: Zero Address");
    _transferOwnership(msg.sender);
    controller = IController(msg.sender);
    baseToken = ERC20(_baseToken);
    quoteToken = ERC20(_quoteToken);
    oracle = IOracle(_oracle);
    WETH = IWETH(weth);
    positionManager = PositionManager(_positionManager);
    initializeConfig();
  }
  
  
  //////// DEOSIT/WITHDRAW FUNCTIONS

  /// @notice Withdraw assets from the ticker
  /// @param liquidity Amount of GEV tokens to redeem; if 0, redeem all
  /// @param token Address of the token redeemed for
  /// @return amount Total token returned
  function withdraw(uint liquidity, address token) public returns (uint amount) {
    amount = _withdraw(msg.sender, liquidity, token);
  }
  

  /// @notice withdraw for another user who placed a withdrawal intent
  /// @dev prevents griefing by diluting the vault yields with funds marked for withdrawals but never withdrawn
  function withdrawOnBehalf(address onBehalfOf, uint liquidity, address token) public onlyOwner returns (uint amount) {
    require(withdrawalIntents[onBehalfOf] >= liquidity, "GEV: Intent Too Low");
    amount = _withdraw(onBehalfOf, liquidity, token);
  }
  
  
  function _withdraw(address user, uint liquidity, address token) internal nonReentrant returns (uint amount){
    require(token == address(baseToken) || token == address(quoteToken), "GEV: Invalid Token");
    require(liquidity <= balanceOf(user), "GEV: Insufficient Balance");
    if(liquidity == 0) liquidity = balanceOf(user);
    if(liquidity == 0) return 0;
    
    (,,uint vaultValueX8) = getReserves();
    uint valueX8 = vaultValueX8 * liquidity / totalSupply();
    amount = valueX8 * 10**ERC20(token).decimals() / oracle.getAssetPrice(token);
    uint fee = amount * getAdjustedBaseFee(token == address(quoteToken)) / FEE_MULTIPLIER;
    
    _burn(user, liquidity);
    withdrawAmm();
    ERC20(token).safeTransfer(controller.treasury(), fee);
    uint bal = amount - fee;

    if (token == address(WETH)){
      WETH.withdraw(bal);
      (bool success, ) = payable(user).call{value: bal}("");
      require(success, "GEV: Error sending ETH");
    }
    else {
      ERC20(token).safeTransfer(user, bal);
    }
    
    // reset withdrawal intent
    totalIntents -= withdrawalIntents[user];
    withdrawalIntents[user] = 0;
    // Check utilization rate after transfer processed
    (uint utilizationRate, uint maxRate) = positionManager.getUtilizationRateStatus();
    require(utilizationRate <= maxRate, "GEV: Utilization Rate too high");
    
    deployAssets();
    emit Withdraw(user, token, amount, liquidity);
  }
  

  


  /// @notice deposit tokens in the pool, convert to WETH if necessary
  /// @param token Token address
  /// @param amount Amount of token deposited
  function deposit(address token, uint amount) public payable nonReentrant returns (uint liquidity) {
    require(amount > 0 || msg.value > 0, "GEV: Deposit Zero");
    require(!controller.isPaused(), "GEV: Pool Disabled");
    require(token == address(baseToken) || token == address(quoteToken), "GEV: Invalid Token");
    
    withdrawAmm();
    (,,uint vaultValueX8) = getReserves();
    uint adjBaseFee = getAdjustedBaseFee(token == address(baseToken));
    // Wrap if necessary and deposit here
    if (msg.value > 0){
      require(token == address(WETH), "GEV: Invalid Weth");
      // wraps ETH by sending to the wrapper that sends back WETH
      WETH.deposit{value: msg.value}();
      amount = msg.value;
    }
    else { 
      ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
    
    // Send deposit fee to treasury
    uint fee = amount * adjBaseFee / FEE_MULTIPLIER;
    ERC20(token).safeTransfer(controller.treasury(), fee);
    uint valueX8 = oracle.getAssetPrice(token) * (amount - fee) / 10**ERC20(token).decimals();
    
    require(tvlCapX8 == 0 || tvlCapX8 > valueX8 + vaultValueX8, "GEV: Max Cap Reached");

    uint tSupply = totalSupply();
    // initial liquidity at 1e18 token ~ $1
    if (tSupply == 0 || vaultValueX8 == 0)
      liquidity = valueX8 * 1e10;
    else
      liquidity = tSupply * valueX8 / vaultValueX8;
    
    deployAssets();
    require(liquidity > 0, "GEV: No Liquidity Added");
    _mint(msg.sender, liquidity);

    // Prevent inflation attack
    if (liquidity == totalSupply()) _mint(0x000000000000000000000000000000000000dEaD, liquidity / 100);
    emit Deposit(msg.sender, token, amount, liquidity);
  }

  
  /// @notice Update a user withdrawal intent
  function setWithdrawalIntent(uint intentAmount) public {
    require(intentAmount <= balanceOf(msg.sender), "GEV: Intent too high");
    uint previousIntent = withdrawalIntents[msg.sender];
    if (previousIntent > 0) totalIntents -= previousIntent;
    withdrawalIntents[msg.sender] = intentAmount;
    totalIntents += intentAmount;
  }
  
  /// @notice Reset withdrawal intent before transfers
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    uint intentAmount = withdrawalIntents[from];
    withdrawalIntents[from] = 0;
    totalIntents -= intentAmount;
  }

  
  //////// BORROWING FUNCTIONS
  
  
  /// @notice Allow an OPM to borrow assets and keep accounting of the debt
  function borrow(address token, uint amount) public onlyOPM nonReentrant {
    require(!controller.isPaused(), "GEV: Pool Disabled");
    withdrawAmm();
    require(ERC20(token).balanceOf(address(this)) >= amount, "GEV: Not Enough Supply");
    
    ERC20(token).safeTransfer(msg.sender, amount);
    deployAssets();
    emit Borrowed(address(token), amount);
  }
  
  
  /// @notice Allows OPM to return funds when a position is closed
  function repay(address token, uint amount, uint fees) public onlyOPM nonReentrant {
    require(amount > 0, "GEV: Invalid Debt");
    withdrawAmm();
    
    if(token == address(quoteToken)) quoteToken.safeTransferFrom(msg.sender, address(this), amount + fees);
    else {
      ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
      quoteToken.safeTransferFrom(msg.sender, address(this), fees);
    }
    oracle.getAssetPrice(address(quoteToken));
    if (fees > 0) {
      uint treasuryFees = fees * controller.treasuryShareX2() / 100;
      quoteToken.safeTransfer(controller.treasury(), treasuryFees);
      uint vaultFees = fees - treasuryFees;
      reserveFees(0, vaultFees, vaultFees * oracle.getAssetPrice(address(quoteToken)) / 10**quoteToken.decimals());
    }
    deployAssets();
    emit Repaid(token, amount);
  }


  //////// INTERNAL FUNCTIONS, OVERRIDEN
  
  /// @notice Get AMM range amounts
  function getAmmAmounts() public view virtual returns (uint baseAmount, uint quoteAmount){}
  /// @notice Withdraw from Amm
  function withdrawAmm() internal virtual returns (uint baseAmount, uint quoteAmount){}
  /// @notice Deposit in Amm
  function depositAmm(uint baseAmount, uint quoteAmount) internal virtual returns (uint liq) {}
  
  
  /// @notice Deploy assets in tickSpread ticks above and below current price
  function deployAssets() internal { 
    if (controller.isPaused()) return;

    uint baseAvail = baseToken.balanceOf(address(this));
    uint quoteAvail = quoteToken.balanceOf(address(this));
    (uint basePending, uint quotePending) = getPendingFees();
    // deposit a part of the assets in the full range. No slippage control in TR since we already checked here for sandwich
    if (baseAvail > basePending && quoteAvail > quotePending) 
      depositAmm((baseAvail - basePending) * ammPositionShareX2 / 100, (quoteAvail - quotePending) * ammPositionShareX2 / 100);
  }
  
  
  /// @notice Get vault underlying assets
  function getReserves() public view returns (uint baseAmount, uint quoteAmount, uint valueX8){
    (baseAmount, quoteAmount) = _getVaultReserves();
    valueX8 = baseAmount  * oracle.getAssetPrice(address(baseToken))  / 10**baseToken.decimals() 
            + quoteAmount * oracle.getAssetPrice(address(quoteToken)) / 10**quoteToken.decimals();
  }
  
  
  /// @notice Get vault reserves adjusted for withdraw intents
  function getAdjustedReserves() public view returns (uint baseAmount, uint quoteAmount){
    (baseAmount, quoteAmount) = _getVaultReserves();
    uint totalSupply = totalSupply();
    if (totalIntents > 0 && totalSupply > 0) {
      uint adjustedShare = totalSupply - totalIntents;
      baseAmount = baseAmount * adjustedShare / totalSupply;
      quoteAmount = quoteAmount * adjustedShare / totalSupply;
    }
  }
  
  
  function _getVaultReserves() private view returns (uint baseAmount, uint quoteAmount){
    (baseAmount, quoteAmount) = getAmmAmounts();
    
    // add borrowed amounts
    (uint baseDue, uint quoteDue) = positionManager.getAssetsDue();
    baseAmount += baseDue + baseToken.balanceOf(address(this));
    quoteAmount += quoteDue + quoteToken.balanceOf(address(this));
    
    // deduce pending fees - should never be larger than balance but check to avoid breaking the pool if that happens
    (uint basePending, uint quotePending) = getPendingFees();
    baseAmount  = basePending < baseAmount ? baseAmount - basePending : 0;
    quoteAmount  = quotePending < quoteAmount ? quoteAmount - quotePending : 0;
  }


  /// @notice Get deposit fee
  /// @param increaseBase Whether (base is added || quote removed) or not
  /// @dev Simple linear model: from baseFeeX4 / 2 to baseFeeX4 * 3 / 2
  function getAdjustedBaseFee(bool increaseBase) public view returns (uint adjustedBaseFeeX4) {
    uint baseFeeX4_ = uint(baseFeeX4);
    (uint baseRes, uint quoteRes, ) = getReserves();
    uint valueBase  = baseRes  * oracle.getAssetPrice(address(baseToken))  / 10**baseToken.decimals();
    uint valueQuote = quoteRes * oracle.getAssetPrice(address(quoteToken)) / 10**quoteToken.decimals();

    if (increaseBase) adjustedBaseFeeX4 = baseFeeX4_ * valueBase  / (valueQuote + 1);
    else              adjustedBaseFeeX4 = baseFeeX4_ * valueQuote / (valueBase  + 1);

    // Adjust from -50% to +50%
    if (adjustedBaseFeeX4 < baseFeeX4_ / 2) adjustedBaseFeeX4 = baseFeeX4_ / 2;
    if (adjustedBaseFeeX4 > baseFeeX4_ * 3 / 2) adjustedBaseFeeX4 = baseFeeX4_ * 3 / 2;
  }


  /// @notice fallback: deposit unless it.s WETH being unwrapped
  receive() external payable {
    if(msg.sender != address(WETH)) deposit(address(WETH), msg.value);
  }
  
  
  /// @notice Helper that checks current allowance and approves if necessary
  /// @param token Target token
  /// @param spender Spender
  /// @param amount Amount below which we need to approve the token spending
  function checkSetApprove(ERC20 token, address spender, uint amount) internal {
    uint currentAllowance = token.allowance(address(this), spender);
    if (currentAllowance < amount) token.safeIncreaseAllowance(spender, UINT256MAX - currentAllowance);
  }


  /// @notice Get the base asset price in quote tokens
  function getBasePrice() public view returns (uint priceX8) {
    priceX8 = oracle.getAssetPrice(address(baseToken)) * 1e8 / oracle.getAssetPrice(address(quoteToken));
  }
  
  
  /// @notice Return underlying tokens
  function tokens() public view returns (address, address){
    return (address(baseToken),  address(quoteToken));
  }
  
  /// @notice Return AMM type, which is none for base vault
  function ammType() public pure virtual returns (bytes32 _ammType){
    _ammType = "";
  }
  

  /// @notice Get the name of this contract token
  function name() public view virtual override returns (string memory) { 
    return string(abi.encodePacked("Rensho ", baseToken.symbol(), "-", quoteToken.symbol()));
  }
  /// @notice Get the symbol of this contract token
  function symbol() public view virtual override returns (string memory _symbol) {
    _symbol = "Good-LP";
  }
  
  function getPastFees(uint period) public view returns (uint baseAmount, uint quoteAmount){
    baseAmount = periodToFees0[period];
    quoteAmount = periodToFees1[period];
  }
}  