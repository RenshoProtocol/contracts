// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


/**
 * @title FeeStreamer
 * @dev Tracks fees accumulated for the current period, while streaming fees for the past period
 * The streamer doesnt actually holds funds, but account for the fees in a given period.
 * In practice, streaming is inverted: a contract call getPendingFees() to know how much of token balances are reserved
 */  
abstract contract FeeStreamer {
  event ReservedFees(uint value);
  
  /// @notice Streaming period in seconds, default daily
  uint internal constant streamingPeriod = 86400;
  /// @notice Fees accumated at a given period
  mapping (uint => uint) internal periodToFees0;
  mapping (uint => uint) internal periodToFees1;
  
  
  /// @notice Add fees to the current period
  function reserveFees(uint amount0, uint amount1, uint value) internal {
    uint period = block.timestamp / streamingPeriod;
    if(amount0 > 0) periodToFees0[period] += amount0;
    if(amount1 > 0) periodToFees1[period] += amount1;
    if(value > 0) emit ReservedFees(value);
  }
  
  
  /// @notice Returns amount of fees reserved, pending streaming
  function getPendingFees() public view returns (uint pendingFees0, uint pendingFees1) {
    // time elapsed in past period:
    uint currentPeriod = block.timestamp / streamingPeriod;
    uint remainingTime = streamingPeriod - block.timestamp % streamingPeriod;
    pendingFees0 = periodToFees0[currentPeriod] + periodToFees0[currentPeriod-1] * remainingTime / streamingPeriod;
    pendingFees1 = periodToFees1[currentPeriod] + periodToFees1[currentPeriod-1] * remainingTime / streamingPeriod;
  }
}