// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

library Types {
    enum OrderStatus {
        Open,
        Opened,
        OpenFail,
        Canceled
    }

    enum PoolAction {
        Deposit,
        Withdraw
    }
    enum PoolActionStatus {
        Submit,
        Success,
        Fail,
        Cancel
    }

    enum OrderType{
        Open,
        Close,
        TriggerOpen,
        Liquidate,
        TakeProfit,
        UserTakeProfit,
        UserStopLoss
    }

    struct Position {
        uint256 id;
        address taker;
        address market;

        int8 direction;
        uint256 amount;
        uint256 value;
        uint256 takerLeverage;
        uint256 takerMargin;

        uint256 makerMargin;
        uint256 makerLeverage;
        uint256 clearAnchorRatio;
        int256 frLastX96;

        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 lastTakerSetTime;

        int256 fundingPayment;
        int256 pnl;

        uint256 lastUpdateTime;
    }

    struct Order {
        uint256 id;

        address market;
        address taker;
        int8 direction;
        uint256 takerLeverage;
        uint256 freezeMargin;
        uint256 amount;
        uint256 clearAnchorRatio;

        uint256 takerOpenDeadline;
        uint256 takerOpenPriceMin;
        uint256 takerOpenPriceMax;

        uint256 triggerPrice;
        // 1: >=; -1:<=
        int8 triggerDirection;
        uint256 activePrice;

        OrderType orderType;
        uint256 riskFunding;

        address inviter;
        uint256 takerFee;
        uint256 feeToInviter;
        uint256 feeToExchange;
        uint256 feeToMaker;

        uint256 tradeTs;
        uint256 tradePrice;
        uint256 tradeIndexPrice;
        uint256 tradeIndexPriceTimestamp;
        int256 rlzPnl;

        int256 fundingPayment;
        int256 frX96;
        int256 frLastX96;
        int256 fundingAmount;

        uint256 deadline;
        uint256 openTime;
        OrderStatus status;
    }

    struct MakerOrder {
        uint256 id;
        address maker;
        uint256 submitBlockHeight;
        uint256 submitBlockTimestamp;
        uint256 price;
        uint256 priceTimestamp;
        uint256 amount;
        uint256 liquidity;
        uint256 feeToPool;
        uint256 cancelBlockHeight;
        uint256 sharePrice;
        int poolTotal;
        int profit;
        PoolAction action;
        PoolActionStatus status;
    }

    struct TradeMathParams {
        Position pos;
        Order openOrder;
        uint256 price;
    }

    struct TradeMathResponse {
        uint256 newAmount;
        uint256 newValue;
        int8 newDirection;
        uint256 newTakerMargin;
        uint256 newMakerMargin;
        int256 newFundingPayment;
        uint256 fee;
        uint256 marginToBalance;
        uint256 marginToPool;
        int256 pnl;
        uint256 feeSettle;
        uint256 feeForNewPosition;

        uint256 deltaAmount;
        uint256 deltaValue;
        uint256 deltaTakerMargin;
        uint256 deltaMakerMargin;
        int256 deltaFundingPayment;
        uint256 feeToInviter;
        uint256 feeToMaker;
        uint256 feeToExchange;
        uint256 amount;

        uint256 updateAmount;
        uint256 updateValue;
        uint256 updateTakerMargin;
        uint256 updateMakerMargin;
    }

    struct OpenInternalParams {
        address _taker;
        uint256 id;
        address inviter;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 margin;
        uint256 amount;
        uint256 leverage;
        int8 direction;
        int8 triggerDirection;
        uint256 triggerPrice;
        uint8 reduceOnly;
        bool isLiquidate;
    }

    struct LiquidityParams {
        uint256 id;
        uint256 price;
        uint256 indexPrice;
        uint256 indexPriceTimestamp;
        OrderType action;
    }

    struct LiquidityCheckParams {
        Types.Position position;
        uint256 price;
    }

    struct LiquidityInfoParams {
        Types.Position position;
        uint256 price;
        uint256 indexPrice;
        OrderType action;
    }

    struct FundingParams {
        address manager;
        address maker;
        Types.Position position;
        uint256 indexPrice;
    }

    struct FundingResponse {
        int256 _fundingGrowthGlobalX96;
        int256 fundingPayment;
    }

    struct LimitConfig {
        int256 fundingRateMax; // 1e7

        uint256 takerLeverageMin;
        uint256 takerLeverageMax;
        uint256 takerMarginMin;
        uint256 takerMarginMax;
        uint256 takerValueMin;
        uint256 takerValueMax;
        uint256 closeOrderNumMax;
        uint256 triggerOrderNumMax;
    }

    struct LiquidateInfoResponse {
        bool isTakerLiq;
        bool isMakerBroke;
        bool isOver;
        int256 pnl;
        uint256 takerFee;
        uint256 feeToMaker;
        uint256 feeToExchange;
        uint256 riskFunding;
    }
}
