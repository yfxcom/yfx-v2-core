// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "../library/Types.sol";

interface IMarket {
    function open(Types.OpenInternalParams memory params) external returns (uint256 id);

    function cancel(uint256 id) external;

    function priceToOpen(uint256 id, uint256 price, uint256 indexPrice, uint256 indexPriceTimestamp) external returns (bool, uint256 _id);

    function resetStatusToFail(uint256 id) external;

    function liquidate(Types.LiquidityParams memory params) external returns (uint256);

    function depositMargin(address _taker, uint256 _id, uint256 _value) external;

    function getPositionId(address _taker) external view returns (uint256);

    function getPosition(uint256 id) external view returns (Types.Position memory);

    function getOpenOrderIds(address _taker) external view returns (uint256[] memory);

    function getOpenOrder(uint256 id) external view returns (Types.Order memory);

    function clearAnchorRatio() external view returns (uint256);

    function initialize(uint256 _indexPrice, address _clearAnchor, uint256 _clearAnchorRatio, address _maker, uint8 _marketType) external;
    //
    function clearAnchorDecimals() external view returns (uint256);

    function leverageDecimals() external view returns (uint256);

    function takerValueLimit() external view returns (uint256);

    function mmDecimal() external view returns (uint256);

    function mm() external view returns (uint256);

    function feeDecimal() external view returns (uint256);

    function feeRate() external view returns (uint256);

    function fundingGrowthGlobalX96() external view returns (int256);

    function lastUpdateTs() external view returns (uint256);

    function marketType() external view returns (uint8);

    function feeInvitorPercent() external view returns (uint256);

    function feeMakerPercent() external view returns (uint256);

    function setStopProfitAndLossPrice(uint256 _id, uint256 _profitPrice, uint256 _stopLossPrice) external;
}
