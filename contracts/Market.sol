// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./interface/IUser.sol";
import "./interface/IMaker.sol";
import "./interface/IERC20.sol";
import "./interface/IManager.sol";
import "./library/SafeMath.sol";
import "./library/SignedSafeMath.sol";
import "./library/TransferHelper.sol";
import "./library/Types.sol";
import "./library/ReentrancyGuard.sol";
import "./library/SafeCast.sol";
import "./interface/IMarketCalc.sol";

contract Market is ReentrancyGuard {
    using SafeMath for uint;
    using SignedSafeMath for int;
    using SignedSafeMath for int8;
    using SafeCast for int;
    using SafeCast for uint;

    uint8 public marketType = 0;

    uint32 public positionID;
    uint32 public openOrderID;
    mapping(uint256 => Types.Order) internal orders;
    mapping(uint256 => Types.Position) internal takerPositions;
    mapping(address => int256) public takerLongValues;
    mapping(address => int256) public takerShortValues;

    address internal clearAnchor;
    uint256 public clearAnchorDecimals;
    uint256 public clearAnchorRatio = 10 ** 10;

    address internal taker;
    address internal maker;
    address internal immutable manager;
    IMarketCalc internal calc;

    uint256 internal indexPriceID;

    uint256 public takerValueLimit = 10 ** 30;
    uint256 public makerLeverageRate = 5;

    uint256 public constant mmDecimal = 1000000;//1e6
    uint256 public mm = 5000;// 1e6

    mapping(address => uint256) internal closeOrderNum;
    mapping(address => uint256) internal triggerOrderNum;

    uint256 public constant feeDecimal = 10000;
    //1e4
    uint256 public feeRate = 10;
    uint256 public feeInvitorPercent = 4000;
    uint256 public feeExchangePercent = 4000;
    uint256 public feeMakerPercent = 2000;
    int256 public fundingGrowthGlobalX96;
    uint256 public lastUpdateTs;

    mapping(address => uint256) internal takerPositionList;
    mapping(address => uint256[]) internal takerOrderList;

    bool internal openPaused = false;
    bool internal setPricePaused = false;
    bool internal openTriggerPaused = false;

    event SetPaused(bool _open, bool _set, bool _openTrigger);
    event Initialize(uint256 _indexPrice, address _clearAnchor, uint256 _clearAnchorRatio, address _maker, uint8 _marketType);
    event SetConfigParams(uint256 _feeRate, uint256 _feeInvitorPercent, uint256 _feeExchangePercent, uint256 _feeMakerPercent,uint256 _ratio, uint256 limit, address _calc, uint256 _mm, uint256 rate);

    constructor(address _manager, address _calc) public {
        manager = _manager;
        calc = IMarketCalc(_calc);
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "caller is not the controller");
        _;
    }

    modifier onlyRouter() {
        require(IManager(manager).checkRouter(msg.sender), "caller is not the router");
        _;
    }

    modifier whenNotOpenPaused() {
        require(!IManager(manager).paused() && !openPaused, "paused");
        _;
    }

    modifier whenNotSetPricePaused() {
        require(!IManager(manager).paused() && !setPricePaused, "paused");
        _;
    }

    function setPaused(bool _open, bool _set, bool _openTrigger) external onlyController {
        openPaused = _open;
        setPricePaused = _set;
        openTriggerPaused = _openTrigger;
        emit SetPaused(_open, _set, _openTrigger);
    }

    function initialize(uint256 _indexPrice, address _clearAnchor, uint256 _clearAnchorRatio, address _maker, uint8 _marketType) external {
        require(msg.sender == manager, "not manager");
        indexPriceID = _indexPrice;
        clearAnchor = _clearAnchor;
        clearAnchorRatio = _clearAnchorRatio;
        maker = _maker;
        taker = IManager(manager).taker();
        marketType = _marketType;
        clearAnchorDecimals = IERC20(clearAnchor).decimals();
        emit Initialize(_indexPrice, _clearAnchor, _clearAnchorRatio, _maker, _marketType);
    }

    function setConfigParams(
        uint256 _feeRate,
        uint256 _feeInvitorPercent,
        uint256 _feeExchangePercent,
        uint256 _feeMakerPercent,
        uint256 _ratio,
        uint256 limit,
        address _calc,
        uint256 _mm,
        uint256 rate
    ) external onlyController {
        require(_feeInvitorPercent.add(_feeMakerPercent).add(_feeExchangePercent) == feeDecimal, "percent all not one");
        require(_feeRate < feeDecimal, "feeRate more than one");
        feeRate = _feeRate;
        feeInvitorPercent = _feeInvitorPercent;
        feeExchangePercent = _feeExchangePercent;
        feeMakerPercent = _feeMakerPercent;
        require(marketType == 2 && _ratio > 0 && limit > 0 && _calc != address(0) && (_mm > 0 && _mm < mmDecimal) && rate > 0, "params error");
        clearAnchorRatio = _ratio;
        takerValueLimit = limit;
        calc = IMarketCalc(_calc);
        mm = _mm;
        makerLeverageRate = rate;
        emit SetConfigParams(_feeRate, _feeInvitorPercent, _feeExchangePercent, _feeMakerPercent, _ratio, limit, _calc, _mm, rate);
    }

    function getPositionId(address _taker) external view returns (uint256){
        return takerPositionList[_taker];
    }

    function getPosition(uint256 id) external view returns (Types.Position memory){
        return takerPositions[id];
    }

    function getOpenOrderIds(address _taker) external view returns (uint256[] memory){
        return takerOrderList[_taker];
    }

    function getOpenOrder(uint256 id) external view returns (Types.Order memory){
        return orders[id];
    }

    function open(Types.OpenInternalParams memory params) external nonReentrant onlyRouter whenNotOpenPaused returns (uint256 id) {
        return _open(params);
    }

    // percent/1e6
    function _open(Types.OpenInternalParams memory params) internal returns (uint256 id) {
        openOrderID++;
        id = openOrderID;
        Types.Order storage openOrder = orders[id];
        openOrder.id = id;
        openOrder.market = address(this);
        openOrder.taker = params._taker;
        openOrder.clearAnchorRatio = clearAnchorRatio;
        openOrder.takerOpenDeadline = block.number.add(IManager(manager).openLongBlockElapse());
        openOrder.takerOpenPriceMin = params.minPrice;
        openOrder.takerOpenPriceMax = params.maxPrice;
        openOrder.inviter = params.inviter;
        openOrder.deadline = block.number.add(IManager(manager).cancelBlockElapse());
        openOrder.triggerPrice = openTriggerPaused ? 0 : params.triggerPrice;
        openOrder.triggerDirection = openTriggerPaused ? int8(0) : params.triggerDirection;
        openOrder.openTime = block.timestamp;

        Types.Position memory position = takerPositions[takerPositionList[params._taker]];

        if (params.reduceOnly == 0) {
            calc.checkParams(manager, address(this), params);
            require(position.amount > 0 ? position.takerLeverage == params.leverage : true, "M_OD");

            uint256 value = params.margin.mul(params.leverage);
            _settleTakerLimitValue(openOrder.taker, params.direction, value.toInt256());
            require(takerLongValues[params._taker] < takerValueLimit.toInt256() && takerShortValues[params._taker] < takerValueLimit.toInt256(), "M_OVP");
            if (params.direction == position.direction) {
                require(params.direction == 1 ? takerLongValues[params._taker].add(position.value.toInt256()) < takerValueLimit.toInt256() : takerShortValues[params._taker].add(position.value.toInt256()) < takerValueLimit.toInt256(), "M_OVB");
            } else {
                require(params.direction == 1 ? takerLongValues[params._taker].sub(position.value.toInt256()).abs() < takerValueLimit : takerShortValues[params._taker].sub(position.value.toInt256()).abs() < takerValueLimit, "M_OVB1");
            }

            require(IUser(taker).balance(clearAnchor, params._taker) >= params.margin, "balance not enough");
            bool success = IUser(taker).transfer(clearAnchor, params._taker, params.margin);
            require(success, "transfer error");

            openOrder.direction = params.direction;
            openOrder.takerLeverage = params.leverage;
            openOrder.freezeMargin = params.margin;
            openOrder.orderType = Types.OrderType.Open;
            if (openOrder.triggerPrice > 0) {
                require(params.triggerDirection == 1 || params.triggerDirection == - 1, "triggerDirection not allow");
                openOrder.orderType = Types.OrderType.TriggerOpen;
                triggerOrderNum[params._taker]++;
                require(triggerOrderNum[params._taker] <= IManager(manager).getLimitConfig(address(this)).triggerOrderNumMax, "M_OTN");
            }
        } else {
            require(position.amount > 0, "M_OA");
            require(position.taker == params._taker, "M_CT");
            require(position.amount >= params.amount, "M_OR");

            openOrder.takerLeverage = position.takerLeverage;
            openOrder.direction = - position.direction;
            openOrder.amount = params.amount;
            openOrder.orderType = Types.OrderType.Close;
            if (!params.isLiquidate) {
                closeOrderNum[params._taker] ++;
                require(closeOrderNum[params._taker] <= IManager(manager).getLimitConfig(address(this)).closeOrderNumMax, "M_OCN");
            }
        }

        openOrder.status = Types.OrderStatus.Open;
        takerOrderList[params._taker].push(id);
    }

    function cancel(uint256 id) external nonReentrant onlyRouter {
        require(orders[id].status == Types.OrderStatus.Open || orders[id].status == Types.OrderStatus.OpenFail, "not open");
        orders[id].status = Types.OrderStatus.Canceled;
        if (orders[id].orderType == Types.OrderType.Close) closeOrderNum[orders[id].taker]--;
        if (orders[id].orderType == Types.OrderType.Open || orders[id].orderType == Types.OrderType.TriggerOpen) {
            uint256 balance = orders[id].freezeMargin;
            uint256 value = balance.mul(orders[id].takerLeverage);
            _settleTakerLimitValue(orders[id].taker, orders[id].direction, - (value.toInt256()));
            TransferHelper.safeTransfer(clearAnchor, taker, balance);
            IUser(taker).receiveToken(clearAnchor, orders[id].taker, balance);
            if (orders[id].orderType == Types.OrderType.TriggerOpen) triggerOrderNum[orders[id].taker]--;
        }
    }

    function resetStatusToFail(uint256 id) public onlyRouter {
        require(orders[id].status == Types.OrderStatus.Open, "not open");
        orders[id].status = Types.OrderStatus.OpenFail;
    }

    function setStopProfitAndLossPrice(uint256 _id, uint256 _profitPrice, uint256 _stopLossPrice) external onlyRouter whenNotSetPricePaused {
        takerPositions[_id].takeProfitPrice = _profitPrice;
        takerPositions[_id].stopLossPrice = _stopLossPrice;
        takerPositions[_id].lastTakerSetTime = block.timestamp;
    }

    function priceToOpen(uint256 id, uint256 price, uint256 indexPrice, uint256 indexPriceTimestamp) external nonReentrant onlyRouter returns (bool, uint256 _id){
        Types.Order storage openOrder = orders[id];
        require(openOrder.id > 0, "order not exist");
        require(openOrder.status == Types.OrderStatus.Open, "status is error");
        if (openOrder.triggerPrice > 0) {
            require(block.number < openOrder.takerOpenDeadline, "M_PD");
            require(calc.checkTriggerCondition(openOrder.triggerPrice, openOrder.triggerDirection, indexPrice), "M_PT");
            openOrder.activePrice = indexPrice;
            triggerOrderNum[openOrder.taker]--;
        } else {
            require(block.number < openOrder.deadline, "deadline");
        }

        require(price >= openOrder.takerOpenPriceMin && price <= openOrder.takerOpenPriceMax, "price not match");

        if (takerPositionList[openOrder.taker] == 0) {
            positionID++;
            takerPositionList[openOrder.taker] = positionID;
            takerPositions[positionID].id = positionID;
            takerPositions[positionID].taker = openOrder.taker;
            takerPositions[positionID].market = address(this);
        }

        Types.Position storage position = takerPositions[takerPositionList[openOrder.taker]];
        if (position.amount == 0) {
            position.clearAnchorRatio = openOrder.clearAnchorRatio;
            position.takerLeverage = openOrder.takerLeverage;
            position.direction = openOrder.direction;
            position.makerLeverage = openOrder.takerLeverage.add(makerLeverageRate - 1).div(makerLeverageRate);
        } else {
            require(position.clearAnchorRatio == openOrder.clearAnchorRatio, "M_OCR");
            require(position.takerLeverage == openOrder.takerLeverage, "leverage error");
        }

        if (openOrder.orderType == Types.OrderType.Close) {
            if (position.amount == 0 || position.direction == openOrder.direction) {
                openOrder.status = Types.OrderStatus.OpenFail;
                return (false, position.id);
            }
            closeOrderNum[openOrder.taker]--;
        } else {
            _settleTakerLimitValue(position.taker, openOrder.direction, - (openOrder.freezeMargin.mul(openOrder.takerLeverage).toInt256()));
        }

        openOrder.frLastX96 = position.frLastX96;
        openOrder.fundingAmount = position.amount.toInt256().mul(position.direction);
        Types.FundingResponse memory fundingResponse = _settleFunding(openOrder.taker, indexPrice);
        openOrder.frX96 = fundingResponse._fundingGrowthGlobalX96;

        Types.TradeMathResponse memory response = calc.trade(Types.TradeMathParams(
                position,
                openOrder,
                price
            ));

        _settle(SettleInternalParams(
                openOrder.inviter,
                response.feeToInviter,
                openOrder.riskFunding,
                response.feeToMaker.add(response.marginToPool),
                position.taker,
                response.marginToBalance,
                response.feeToExchange
            ));

        openOrder.feeToExchange = response.feeToExchange;
        openOrder.feeToMaker = response.feeToMaker;
        openOrder.feeToInviter = response.feeToInviter;

        if (response.deltaAmount > 0) {
            openOrder.amount = response.deltaAmount;
            IMaker(maker).closeUpdate(response.deltaMakerMargin, response.deltaTakerMargin, response.deltaAmount, response.deltaValue, - response.pnl, response.feeToMaker, response.deltaFundingPayment, position.direction);
            openOrder.fundingPayment = response.deltaFundingPayment;
            response.feeToMaker = 0;
        }

        if (response.updateAmount > 0) {
            bool success = IMaker(maker).open(response.updateMakerMargin);
            require(success, "maker open fail");
            if (response.deltaAmount == 0) {
                openOrder.amount = response.updateAmount;
            }
            IMaker(maker).openUpdate(response.updateMakerMargin, response.updateTakerMargin, response.updateAmount, response.updateValue, response.feeToMaker, openOrder.direction);
            if (response.newDirection == 1) {
                require(takerLongValues[position.taker].add(response.newValue.toInt256()) <= takerValueLimit.toInt256(), "M_PVB");
            } else {
                require(takerShortValues[position.taker].add(position.value.toInt256()) <= takerValueLimit.toInt256(), "M_PVB1");
            }
        }

        if ((response.updateAmount > 0 && response.deltaAmount > 0) || response.newAmount == 0) {
            position.stopLossPrice = 0;
            position.takeProfitPrice = 0;
            position.lastTakerSetTime = 0;
        }

        if (response.deltaFundingPayment != 0) IMaker(maker).fundingPaymentUpdate(- response.deltaFundingPayment);

        openOrder.tradeTs = block.timestamp;
        openOrder.tradePrice = price;
        openOrder.tradeIndexPrice = indexPrice;
        openOrder.tradeIndexPriceTimestamp = indexPriceTimestamp;
        openOrder.takerFee = response.fee;
        openOrder.rlzPnl = response.pnl;
        openOrder.status = Types.OrderStatus.Opened;

        position.direction = response.newDirection;
        position.amount = response.newAmount;
        position.makerMargin = response.newMakerMargin;
        position.value = response.newValue;
        position.takerMargin = response.newTakerMargin;
        position.pnl = position.pnl.add(response.pnl);
        position.fundingPayment = response.newFundingPayment;
        position.lastUpdateTime = position.amount > 0 ? block.timestamp : 0;

        if (position.amount > 0) {
            bool isPass = calc.isLiquidity(Types.LiquidityCheckParams(position, price));
            require(isPass, "M_OC");
        }
        return (true, position.id);
    }

    struct LiquidateInternalParams {
        uint256 orderId;
        Types.FundingResponse fundingResponse;
    }

    function liquidate(Types.LiquidityParams memory params) public nonReentrant onlyRouter returns (uint256) {
        LiquidateInternalParams memory internalParams = LiquidateInternalParams(0, Types.FundingResponse(0, 0));
        Types.Position storage position = takerPositions[params.id];
        require(position.amount > 0, "order not exist");

        internalParams.orderId = _open(Types.OpenInternalParams(position.taker, 0, address(0), 0, 0, 0, position.amount, position.takerLeverage, position.direction, 0, 0, 1, true));
        Types.Order storage order = orders[internalParams.orderId];

        order.frLastX96 = position.frLastX96;
        order.fundingAmount = position.amount.toInt256().mul(position.direction);
        internalParams.fundingResponse = _settleFunding(position.taker, params.indexPrice);
        order.frX96 = internalParams.fundingResponse._fundingGrowthGlobalX96;
        order.fundingPayment = position.fundingPayment;

        Types.LiquidateInfoResponse memory response = calc.getLiquidateInfo(Types.LiquidityInfoParams(position, params.price, params.indexPrice, params.action));

        order.takerFee = response.takerFee;
        order.feeToMaker = response.feeToMaker;
        order.feeToExchange = response.feeToExchange;
        order.orderType = params.action;
        order.riskFunding = response.riskFunding;

        IMaker(maker).closeUpdate(position.makerMargin, position.takerMargin, position.amount, position.value, - response.pnl, order.feeToMaker, position.fundingPayment, position.direction);

        _settle(SettleInternalParams(
                address(0),
                0,
                order.riskFunding,
                position.makerMargin.toInt256().add(position.fundingPayment).add(- response.pnl).toUint256().add(order.feeToMaker),
                position.taker,
                position.takerMargin.toInt256().add(- position.fundingPayment).add(response.pnl).toUint256().sub(order.takerFee).sub(order.riskFunding),
                order.feeToExchange
            ));
        IMaker(maker).fundingPaymentUpdate(- position.fundingPayment);
        order.rlzPnl = response.pnl;
        order.status = Types.OrderStatus.Opened;
        order.tradeTs = block.timestamp;
        order.tradePrice = params.price;
        order.amount = position.amount;
        order.tradeIndexPrice = params.indexPrice;
        order.tradeIndexPriceTimestamp = params.indexPriceTimestamp;

        position.amount = 0;
        position.frLastX96 = fundingGrowthGlobalX96;
        position.takerLeverage = 0;
        position.makerLeverage = 0;
        position.makerMargin = 0;
        position.takerMargin = 0;
        position.value = 0;
        position.direction = 0;
        position.pnl = position.pnl.add(order.rlzPnl);
        position.fundingPayment = 0;
        position.lastUpdateTime = 0;
        position.stopLossPrice = 0;
        position.takeProfitPrice = 0;
        position.lastTakerSetTime = 0;
        return order.id;
    }

    function _settleTakerLimitValue(address trader, int8 direction, int256 value) internal {
        direction == 1 ? takerLongValues[trader] = takerLongValues[trader].add(value) : takerShortValues[trader] = takerShortValues[trader].add(value);
    }

    struct SettleInternalParams {
        address inviter;
        uint256 feeToInviter;
        uint256 riskFunding;
        uint256 toMaker;
        address _taker;
        uint256 toTaker;
        uint256 feeToExchange;
    }

    function _settle(SettleInternalParams memory params) internal {
        //to riskfunding
        if (params.riskFunding > 0) {
            TransferHelper.safeTransfer(clearAnchor, IManager(manager).riskFundingOwner(), params.riskFunding);
        }

        //to inviter
        if (params.inviter != address(0)) {
            TransferHelper.safeTransfer(clearAnchor, params.inviter, params.feeToInviter);
        }
        //to maker
        if (params.toMaker > 0) {
            TransferHelper.safeTransfer(clearAnchor, maker, params.toMaker);
        }
        //to exchange
        if (params.feeToExchange > 0) {
            TransferHelper.safeTransfer(clearAnchor, IManager(manager).feeOwner(), params.feeToExchange);
        }
        //to taker
        if (params.toTaker > 0) {
            TransferHelper.safeTransfer(clearAnchor, taker, params.toTaker);
            IUser(taker).receiveToken(clearAnchor, params._taker, params.toTaker);
        }
    }

    function _settleFunding(address _taker, uint256 indexPrice) internal returns (Types.FundingResponse memory){
        Types.Position storage position = takerPositions[takerPositionList[_taker]];

        Types.FundingResponse memory response = calc.getFunding(Types.FundingParams(manager, maker, position, indexPrice));
        if (block.timestamp != lastUpdateTs) {
            lastUpdateTs = block.timestamp;
            fundingGrowthGlobalX96 = response._fundingGrowthGlobalX96;
        }
        position.frLastX96 = response._fundingGrowthGlobalX96;

        if (response.fundingPayment != 0) {
            position.fundingPayment = position.fundingPayment.add(response.fundingPayment);
            IMaker(maker).fundingPaymentUpdate(response.fundingPayment);
        }
        return response;
    }

    function depositMargin(address _taker, uint256 id, uint256 _value) external nonReentrant onlyRouter {
        takerPositions[id].takerMargin = takerPositions[id].takerMargin.add(_value);
        require(takerPositions[id].makerMargin >= takerPositions[id].takerMargin, 'margin is error');

        require(IUser(taker).balance(clearAnchor, _taker) >= _value, "balance not enough");
        bool success = IUser(taker).transfer(clearAnchor, _taker, _value);
        require(success, "transfer error");
        IMaker(maker).takerDepositMarginUpdate(_value);
    }
}
