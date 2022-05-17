// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "../library/Types.sol";

interface IMarketCalc {
    function trade(Types.TradeMathParams memory params) external pure returns (Types.TradeMathResponse memory response);

    function checkTriggerCondition(uint256 triggerPrice, int8 triggerDirection, uint256 priceIndex) external pure returns (bool);

    function isLiquidity(Types.LiquidityCheckParams memory params) external view returns (bool);

    function checkParams(address manager, address market, Types.OpenInternalParams memory params) external view;

    function getFunding(Types.FundingParams memory params) external view returns (Types.FundingResponse memory response);

    function getLiquidateInfo(Types.LiquidityInfoParams memory params) external view returns (Types.LiquidateInfoResponse memory response);
}
