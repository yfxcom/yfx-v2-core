// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./library/SafeMath.sol";
import "./library/SignedSafeMath.sol";
import "./library/Types.sol";
import "./library/SafeCast.sol";
import './interface/IMarket.sol';
import './interface/IManager.sol';
import "./interface/IMaker.sol";

contract MarketCalc {
    using SafeMath for uint;
    using SignedSafeMath for int;
    using SignedSafeMath for int8;
    using SafeCast for int;
    using SafeCast for uint;

    uint256 public constant clearAnchorRatioDecimals = 10;
    uint256 public constant priceDecimals = 10;
    uint256 public constant amountDecimals = 10;
    uint256 public constant leverageDecimals = 10;
    uint256 public constant FULLY_CLOSED_RATIO = 1e18;
    int256 public constant Q96 = 0x1000000000000000000000000;
    int256 public constant FUNDING_FEE_RATIO = 1 days;

    struct TradeInternalParams {
        uint256 feeRate;
        uint256 feeDecimal;
        uint8 marketType;
        uint256 deltaMargin;
        uint256 deltaAmount;
        uint256 deltaValue;
        uint256 clearAnchorDecimals;
        uint256 feeInvitorPercent;
        uint256 feeMakerPercent;
    }

    function trade(Types.TradeMathParams memory params) external view returns (Types.TradeMathResponse memory response){
        require(params.openOrder.direction == 1 || params.openOrder.direction == - 1, "direction error");

        TradeInternalParams memory iParams = TradeInternalParams(0, 0, 0, 0, 0, 0, 0, 0, 0);

        iParams.feeRate = IMarket(params.pos.market).feeRate();
        iParams.feeDecimal = IMarket(params.pos.market).feeDecimal();
        iParams.marketType = IMarket(params.pos.market).marketType();
        iParams.clearAnchorDecimals = IMarket(params.pos.market).clearAnchorDecimals();
        iParams.feeInvitorPercent = IMarket(params.pos.market).feeInvitorPercent();
        iParams.feeMakerPercent = IMarket(params.pos.market).feeMakerPercent();

        if (params.openOrder.orderType != Types.OrderType.Close) {
            iParams.deltaMargin = params.openOrder.freezeMargin;
            if (iParams.marketType == 2) {
                iParams.deltaMargin = iParams.deltaMargin.mul(10 ** clearAnchorRatioDecimals).div(params.pos.clearAnchorRatio);
            }

            iParams.deltaValue = iParams.deltaMargin.mul(params.openOrder.takerLeverage);
            if (iParams.marketType == 0 || iParams.marketType == 2) {
                response.amount = iParams.deltaMargin.mul(params.openOrder.takerLeverage).mul(10 ** amountDecimals).mul(10 ** priceDecimals).div(params.price).div(10 ** iParams.clearAnchorDecimals);
            } else {
                response.amount = iParams.deltaMargin.mul(params.openOrder.takerLeverage).mul(params.price).mul(10 ** amountDecimals).div(10 ** priceDecimals).div(10 ** iParams.clearAnchorDecimals);
            }
        } else {
            params.pos.amount > params.openOrder.amount ? response.amount = params.openOrder.amount : response.amount = params.pos.amount;
            if (iParams.marketType == 0 || iParams.marketType == 2) {
                iParams.deltaValue = response.amount.mul(params.price).mul(10 ** iParams.clearAnchorDecimals).div(10 ** amountDecimals).div(10 ** priceDecimals);
            } else {
                iParams.deltaValue = response.amount.mul(10 ** iParams.clearAnchorDecimals).mul(10 ** priceDecimals).div(params.price).div(10 ** amountDecimals);
            }
        }

        if (params.pos.direction.mul(params.openOrder.direction) > 0) {
            response.newAmount = params.pos.amount.add(response.amount);
            response.newValue = params.pos.value.add(iParams.deltaValue);
            response.newDirection = params.openOrder.direction;
            response.newTakerMargin = params.pos.takerMargin.add(params.openOrder.freezeMargin);
            response.deltaMakerMargin = params.openOrder.freezeMargin.mul(params.pos.takerLeverage.div(params.pos.makerLeverage));
            response.newMakerMargin = params.pos.makerMargin.add(response.deltaMakerMargin);

            response.pnl = 0;
            response.marginToBalance = 0;
            if (iParams.marketType == 2) {
                response.fee = iParams.deltaValue.mul(params.pos.clearAnchorRatio).div(10 ** clearAnchorRatioDecimals).mul(iParams.feeRate).div(iParams.feeDecimal);
            } else {
                response.fee = iParams.deltaValue.mul(iParams.feeRate).div(iParams.feeDecimal);
            }

            response.newTakerMargin = response.newTakerMargin.sub(response.fee);
            response.marginToPool = 0;

            response.updateAmount = response.amount;
            response.updateMakerMargin = response.deltaMakerMargin;
            response.updateTakerMargin = params.openOrder.freezeMargin.sub(response.fee);
            response.updateValue = iParams.deltaValue;

            response.deltaAmount = 0;
            response.newFundingPayment = params.pos.fundingPayment;
        } else {
            uint256 closeRatio = response.amount.mul(FULLY_CLOSED_RATIO).div(params.pos.amount);
            if (params.pos.amount >= response.amount) {
                uint256 settleTakerMargin = params.pos.takerMargin.mul(closeRatio).div(FULLY_CLOSED_RATIO);
                uint256 settleMakerMargin = params.pos.makerMargin.mul(closeRatio).div(FULLY_CLOSED_RATIO);
                uint256 settleValue = params.pos.value.mul(closeRatio).div(FULLY_CLOSED_RATIO);
                response.newTakerMargin = params.pos.takerMargin.sub(settleTakerMargin);
                response.newMakerMargin = params.pos.makerMargin.sub(settleMakerMargin);
                response.newAmount = params.pos.amount.sub(response.amount);
                response.newDirection = params.pos.direction;
                response.newValue = params.pos.value.sub(settleValue);

                response.pnl = iParams.deltaValue.toInt256().sub(settleValue.toInt256());
                if (iParams.marketType == 1) response.pnl = - response.pnl;
                if (iParams.marketType == 2) response.pnl = response.pnl.mul(params.pos.clearAnchorRatio.toInt256()).div((10 ** clearAnchorRatioDecimals).toInt256());

                response.pnl = response.pnl.mul(params.pos.direction);

                if (iParams.marketType == 2) {
                    response.fee = iParams.deltaValue.mul(params.pos.clearAnchorRatio).div(10 ** clearAnchorRatioDecimals).mul(iParams.feeRate).div(iParams.feeDecimal);
                } else {
                    response.fee = iParams.deltaValue.mul(iParams.feeRate).div(iParams.feeDecimal);
                }

                response.deltaValue = settleValue;
                response.deltaAmount = response.amount;
                response.deltaTakerMargin = settleTakerMargin;
                response.deltaMakerMargin = settleMakerMargin;
                response.deltaFundingPayment = params.pos.fundingPayment.mul(closeRatio.toInt256()).div(FULLY_CLOSED_RATIO.toInt256());
                response.newFundingPayment = params.pos.fundingPayment.sub(response.deltaFundingPayment);

                require(- response.pnl <= settleTakerMargin.toInt256().add(- response.deltaFundingPayment).sub(response.fee.toInt256()), "MC_T_MM");
                require(response.pnl <= settleMakerMargin.toInt256().add(response.deltaFundingPayment), "MC_T_TM");

                response.marginToBalance = (settleTakerMargin.add(params.openOrder.freezeMargin).toInt256().add(response.pnl).add(- response.deltaFundingPayment)).toUint256().sub(response.fee);
                response.marginToPool = (settleMakerMargin.toInt256().add(- response.pnl).add(response.deltaFundingPayment)).toUint256();

                response.updateAmount = 0;
            } else {
                uint256 settleMargin = params.openOrder.freezeMargin.mul(1e18).div(closeRatio);
                uint256 settleValue = iParams.deltaValue.mul(1e18).div(closeRatio);
                response.newTakerMargin = params.openOrder.freezeMargin.sub(settleMargin);
                response.newMakerMargin = response.newTakerMargin.mul(params.pos.takerLeverage.div(params.pos.makerLeverage));
                response.newAmount = response.amount.sub(params.pos.amount);
                response.newValue = iParams.deltaValue.sub(settleValue);
                response.newDirection = params.openOrder.direction;

                response.pnl = settleValue.toInt256().sub(params.pos.value.toInt256());
                if (iParams.marketType == 1) response.pnl = - response.pnl;
                if (iParams.marketType == 2) response.pnl = response.pnl.mul(params.pos.clearAnchorRatio.toInt256()).div((10 ** clearAnchorRatioDecimals).toInt256());

                response.pnl = response.pnl.mul(params.pos.direction);

                if (iParams.marketType == 2) {
                    response.fee = iParams.deltaValue.mul(params.pos.clearAnchorRatio).div(10 ** clearAnchorRatioDecimals).mul(iParams.feeRate).div(iParams.feeDecimal);
                } else {
                    response.fee = iParams.deltaValue.mul(iParams.feeRate).div(iParams.feeDecimal);
                }

                response.feeSettle = response.fee.mul(FULLY_CLOSED_RATIO).div(closeRatio);
                response.feeForNewPosition = response.fee.sub(response.feeSettle);

                response.newTakerMargin = response.newTakerMargin.sub(response.feeForNewPosition);

                response.deltaValue = params.pos.value;
                response.deltaAmount = params.pos.amount;
                response.deltaTakerMargin = params.pos.takerMargin;
                response.deltaMakerMargin = params.pos.makerMargin;
                response.deltaFundingPayment = params.pos.fundingPayment;
                response.newFundingPayment = 0;

                require(- response.pnl <= params.pos.takerMargin.toInt256().add(- response.deltaFundingPayment).sub(response.feeSettle.toInt256()), "MC_T_MC");
                require(response.pnl <= params.pos.makerMargin.toInt256().add(response.deltaFundingPayment), "MC_T_TC");

                response.marginToBalance = settleMargin.add(params.pos.takerMargin).toInt256().add(response.pnl).add(- response.deltaFundingPayment).sub(response.feeSettle.toInt256()).toUint256();
                response.marginToPool = params.pos.makerMargin.toInt256().add(- response.pnl).add(response.deltaFundingPayment).toUint256();

                response.updateAmount = response.newAmount;
                response.updateMakerMargin = response.newMakerMargin;
                response.updateTakerMargin = response.newTakerMargin;
                response.updateValue = response.newValue;
            }
        }

        if (params.openOrder.inviter != address(0)) {
            response.feeToInviter = response.fee.mul(iParams.feeInvitorPercent).div(iParams.feeDecimal);
        }
        response.feeToMaker = response.fee.mul(iParams.feeMakerPercent).div(iParams.feeDecimal);
        response.feeToExchange = response.fee.sub(response.feeToInviter).sub(response.feeToMaker);

        return response;
    }

    function checkTriggerCondition(uint256 triggerPrice, int8 triggerDirection, uint256 priceIndex) external view returns (bool){
        if (triggerDirection == 1) {
            return priceIndex >= triggerPrice;
        } else {
            return priceIndex <= triggerPrice;
        }
    }

    struct LiquidityInternalParams {
        uint8 marketType;
        uint256 clearAnchorDecimals;
        Types.FundingResponse fundingResponse;
        uint256 mm;
        uint256 mmDecimal;
        uint256 takerBrokePrice;
        uint256 takerLiqPrice;
        uint256 feeRate;
        uint256 feeDecimal;
        uint256 feeMakerPercent;
    }

    function getLiquidateInfo(Types.LiquidityInfoParams memory params) public view returns (Types.LiquidateInfoResponse memory response) {
        LiquidityInternalParams memory iParams = LiquidityInternalParams(0, 0, Types.FundingResponse(0, 0), 0, 0, 0, 0, 0, 0, 0);

        iParams.marketType = IMarket(params.position.market).marketType();
        iParams.clearAnchorDecimals = IMarket(params.position.market).clearAnchorDecimals();
        iParams.mm = IMarket(params.position.market).mm();
        iParams.mmDecimal = IMarket(params.position.market).mmDecimal();
        iParams.feeRate = IMarket(params.position.market).feeRate();
        iParams.feeDecimal = IMarket(params.position.market).feeDecimal();
        iParams.feeMakerPercent = IMarket(params.position.market).feeMakerPercent();
        
        uint256 closeValue;
        if (iParams.marketType == 0 || iParams.marketType == 2) {
            closeValue = params.position.amount.mul(params.price).mul(10 ** iParams.clearAnchorDecimals).div(10 ** amountDecimals).div(10 ** priceDecimals);
            if (iParams.marketType == 2) {
                closeValue = closeValue.mul(params.position.clearAnchorRatio).div(10 ** clearAnchorRatioDecimals);
            }
        } else {
            closeValue = params.position.amount.mul(10 ** iParams.clearAnchorDecimals).mul(10 ** priceDecimals).div(params.price).div(10 ** amountDecimals);
        }

        response.takerFee = closeValue.mul(iParams.feeRate).div(iParams.feeDecimal);
        response.feeToMaker = response.takerFee.mul(iParams.feeMakerPercent).div(iParams.feeDecimal);
        response.feeToExchange = response.takerFee.sub(response.feeToMaker);

        if (params.action == Types.OrderType.Liquidate) {
            response.takerFee = 0;
            response.feeToMaker = 0;
            response.feeToExchange = 0;

            (response.pnl,) = getUnPNL(params.position, params.price);
        } else if (params.action == Types.OrderType.TakeProfit) {
            response.pnl = params.position.makerMargin.toInt256().add(params.position.fundingPayment);
        } else if (params.action == Types.OrderType.UserTakeProfit || params.action == Types.OrderType.UserStopLoss) {
            (response.pnl,) = getUnPNL(params.position, params.price);
        }

        if (params.position.takerMargin.toInt256().sub(params.position.fundingPayment).sub(response.takerFee.toInt256()).add(response.pnl) < 0) {
            response.pnl = - (params.position.takerMargin.toInt256().sub(params.position.fundingPayment).sub(response.takerFee.toInt256()));
        }

        if (params.position.makerMargin.toInt256().add(params.position.fundingPayment).sub(response.pnl) < 0) {
            response.pnl = params.position.makerMargin.toInt256().add(params.position.fundingPayment);
        }

        if (params.action == Types.OrderType.Liquidate) {
            response.riskFunding = params.position.takerMargin.toInt256().sub(params.position.fundingPayment).add(response.pnl).toUint256();
        }

        return response;
    }

    function isLiquidity(Types.LiquidityCheckParams memory params) public view returns (bool) {
        (int256 pnl, uint256 nowValue) = getUnPNL(params.position, params.price);

        bool isTakerLiq = params.position.takerMargin.toInt256().sub(params.position.fundingPayment).add(pnl) <= nowValue.mul(IMarket(params.position.market).mm()).div(IMarket(params.position.market).mmDecimal()).toInt256();
        bool isMakerBroke = pnl.sub(params.position.fundingPayment) >= params.position.makerMargin.toInt256();
        return !isTakerLiq && !isMakerBroke;
    }

    function getUnPNL(Types.Position memory position, uint256 price) internal view returns (int256 pnl, uint256 nowValue){
        uint8 marketType = IMarket(position.market).marketType();
        uint256 clearAnchorDecimals = IMarket(position.market).clearAnchorDecimals();
        if (marketType == 0 || marketType == 2) {
            nowValue = price.mul(position.amount).mul(10 ** clearAnchorDecimals).div(10 ** (priceDecimals + amountDecimals));
            pnl = nowValue.toInt256().sub(position.value.toInt256());
            if (marketType == 2) {
                pnl = pnl.mul(position.clearAnchorRatio.toInt256()).div((10 ** clearAnchorRatioDecimals).toInt256());
                nowValue = nowValue.mul(position.clearAnchorRatio).div(10 ** clearAnchorRatioDecimals);
            }
        } else {
            nowValue = position.amount.mul(10 ** priceDecimals).mul(10 ** clearAnchorDecimals).div(price).div(10 ** amountDecimals);
            pnl = position.value.toInt256().sub(nowValue.toInt256());
        }

        pnl = pnl.mul(position.direction);
    }

    struct FundingInternalParams {
        uint256 longAmount;
        uint256 shortAmount;
        uint256 clearAnchorDecimals;
        int256 fundingGrowthGlobalX96;
        int256 dealtX96;
        int256 dealtFundingRate;
        Types.LimitConfig config;
        uint8 marketType;
        uint256 lastTs;
    }

    function getFunding(Types.FundingParams memory params) public view returns (Types.FundingResponse memory response){
        FundingInternalParams memory iParams = FundingInternalParams(0, 0, 0, 0, 0, 0, Types.LimitConfig(0, 0, 0, 0, 0, 0, 0, 0, 0), 0, 0);
        iParams.clearAnchorDecimals = IMarket(params.position.market).clearAnchorDecimals();
        iParams.fundingGrowthGlobalX96 = IMarket(params.position.market).fundingGrowthGlobalX96();
        iParams.config = IManager(params.manager).getLimitConfig(params.position.market);
        iParams.marketType = IMarket(params.position.market).marketType();
        iParams.lastTs = block.timestamp.sub(IMarket(params.position.market).lastUpdateTs());

        if (block.timestamp == IMarket(params.position.market).lastUpdateTs() || IMarket(params.position.market).lastUpdateTs() == 0) {
            response._fundingGrowthGlobalX96 = iParams.fundingGrowthGlobalX96;
        } else {
            (iParams.longAmount, iParams.shortAmount) = IMaker(params.maker).getAmount();
            if (iParams.longAmount.add(iParams.shortAmount) != 0) {
                iParams.dealtFundingRate = (iParams.longAmount.toInt256().sub(iParams.shortAmount.toInt256()) ** 3).mul(iParams.config.fundingRateMax).div(iParams.longAmount.toInt256().add(iParams.shortAmount.toInt256()) ** 3);
                if (iParams.dealtFundingRate > iParams.config.fundingRateMax) iParams.dealtFundingRate = iParams.config.fundingRateMax;
                if (iParams.dealtFundingRate < - iParams.config.fundingRateMax) iParams.dealtFundingRate = - iParams.config.fundingRateMax;
                iParams.dealtFundingRate = iParams.dealtFundingRate.mul(Q96).div(1e7).div(FUNDING_FEE_RATIO);
                if (iParams.marketType == 0 || iParams.marketType == 2) {
                    iParams.dealtX96 = iParams.dealtFundingRate.mul(params.indexPrice.mul(iParams.lastTs).div(10 ** priceDecimals).toInt256());
                } else {
                    iParams.dealtX96 = iParams.dealtFundingRate.mul(iParams.lastTs.mul(10 ** priceDecimals).toInt256()).div(params.indexPrice.toInt256());
                }
            } else {
                iParams.dealtX96 = 0;
            }

            response._fundingGrowthGlobalX96 = iParams.fundingGrowthGlobalX96.add(iParams.dealtX96);
        }

        response.fundingPayment = params.position.amount.toInt256().mul(response._fundingGrowthGlobalX96.sub(params.position.frLastX96)).mul(params.position.direction).mul((10 ** iParams.clearAnchorDecimals).toInt256()).div((10 ** amountDecimals).toInt256()).div(Q96);
        if (iParams.marketType == 2) {
            response.fundingPayment = response.fundingPayment.mul(params.position.clearAnchorRatio.toInt256()).div((10 ** clearAnchorRatioDecimals).toInt256());
        }
        return response;
    }

    function checkParams(address manager, address market, Types.OpenInternalParams memory params) external view {
        Types.LimitConfig memory _config = IManager(manager).getLimitConfig(market);
        require(params.direction == 1 || params.direction == - 1, "direction not allow");
        require(_config.takerLeverageMin <= params.leverage && params.leverage <= _config.takerLeverageMax, "leverage not allow");
        require(_config.takerMarginMin <= params.margin && params.margin <= _config.takerMarginMax, "margin not allow");
        require(_config.takerValueMin <= params.margin.mul(params.leverage) && params.margin.mul(params.leverage) <= _config.takerValueMax, "value not allow");
    }

}
