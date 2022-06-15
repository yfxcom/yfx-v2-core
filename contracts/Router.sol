// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./interface/IMarket.sol";
import "./interface/IMaker.sol";
import './interface/IManager.sol';
import "./library/Types.sol";
import "./interface/IMarketCalc.sol";

contract Router {
    address manager;
    IMarketCalc immutable calc;

    event TakerOpen(address market, uint256 id);
    event Open(address market, uint256 id, uint256 orderid);
    event TakerClose(address market, uint256 id);
    event DepositMargin(address market, uint256 id);
    event Liquidate(address market, uint256 id, uint256 orderid);
    event TakeProfit(address market, uint256 id, uint256 orderid);
    event Cancel(address market, uint256 id);
    event ChangeStatus(address market, uint256 id);
    event AddLiquidity(uint id, address makeraddress, uint amount, uint256 deadline);
    event RemoveLiquidity(uint id, address makeraddress, uint liquidity, uint256 deadline);
    event CancelAddLiquidity(uint id, address makeraddress);
    event PriceToAddLiquidity(uint id, address makeraddress);
    event PriceToRemoveLiquidity(uint id, address makeraddress);
    event CancelRemoveLiquidity(uint id, address makeraddress);
    event SetStopProfitAndLossPrice(uint256 id, address market, uint256 _profitPrice, uint256 _stopLossPrice);

    constructor(address _manager, IMarketCalc _calc) public {
        require(_manager != address(0), "Router:constructor _manager is zero address");
        manager = _manager;
        calc = _calc;
    }

    modifier onlyPriceProvider() {
        require(IManager(manager).checkSigner(msg.sender), "Router: caller is not the priceprovider");
        require(address(0) != msg.sender, "Router: caller is not the priceprovider");
        _;
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'Router: EXPIRED');
        _;
    }

    modifier onlyMakerOrMarket(address _marketOrMaker){
        (bool isMarket) = IManager(manager).checkMarket(_marketOrMaker);
        (bool isMaker) = IManager(manager).checkMaker(_marketOrMaker);
        require(isMarket || isMaker, "Router: no permission!");
        _;
    }

    /// @notice user open position parameters
    struct TakerOpenParams {
        address _market; // market contract address
        address inviter; // inviter address
        uint128 minPrice;// min price for the slippage
        uint128 maxPrice;// max price for the slippage
        uint256 margin; // margin to open
        uint16 leverage;
        int8 direction; // order direction, 1: long, -1: short
        int8 triggerDirection; // price condition for trigger orders, 1 : index price >= trigger price, -1 : index price <= trigger price
        uint256 triggerPrice;
        uint256 deadline;
    }

    /// @notice user close position parameters
    struct TakerCloseParams {
        address _market; // market contract address
        uint256 id; // position id
        address inviter; // inviter address
        uint128 minPrice; // min price for the slippage
        uint128 maxPrice; // max price for the slippage
        uint256 amount; // close order amount
        uint256 deadline;
    }

    /// @notice user place an open-position order, long or short
    /// @param params see the struct declaration
    /// @return the order id
    function takerOpen(TakerOpenParams memory params) external ensure(params.deadline) onlyMakerOrMarket(params._market) returns (uint256 id) {
        require(params.minPrice <= params.maxPrice, "Router: error price for taker open");
        id = IMarket(params._market).open(Types.OpenInternalParams({
        _taker : msg.sender,
        id : 0,
        inviter : params.inviter,
        minPrice : params.minPrice,
        maxPrice : params.maxPrice,
        margin : params.margin,
        amount : 0,
        leverage : params.leverage,
        direction : params.direction,
        triggerDirection : params.triggerDirection,
        triggerPrice : params.triggerPrice,
        reduceOnly : 0,
        isLiquidate : false
        }));
        emit TakerOpen(params._market, id);
    }

    /// @notice user place a close-position order
    /// @param params see the struct declaration
    /// @return order id
    function takerClose(TakerCloseParams memory params) external ensure(params.deadline) onlyMakerOrMarket(params._market) returns (uint256 id) {
        require(params.minPrice <= params.maxPrice, "Router: error price for taker close");
        id = IMarket(params._market).open(Types.OpenInternalParams({
        _taker : msg.sender,
        id : params.id,
        inviter : params.inviter,
        minPrice : params.minPrice,
        maxPrice : params.maxPrice,
        margin : 0,
        amount : params.amount,
        leverage : 0,
        direction : 0,
        triggerDirection : 0,
        triggerPrice : 0,
        reduceOnly : 1,
        isLiquidate : false
        }));

        emit TakerClose(params._market, id);
    }

    /// @notice user cancel an order that either open or failed
    /// @param _market market address
    /// @param id order id
    function takerCancel(address _market, uint256 id) external onlyMakerOrMarket(_market) {
        require(getOpenOrder(_market, id).taker == msg.sender, "Router: not owner");
        require(getOpenOrder(_market, id).deadline < block.number, "Router: can not cancel until deadline");
        IMarket(_market).cancel(id);
        emit Cancel(_market, id);
    }

    /// @notice centralized oracle set the trade price for an open order
    /// @param _market  market address
    /// @param id   order id
    /// @param price    trade price
    /// @param indexPrice   current index price
    /// @param indexPriceTimestamp  timestamp
    function priceToOpen(
        address _market,
        uint256 id,
        uint256 price,
        uint256 indexPrice,
        uint256 indexPriceTimestamp
    ) external onlyPriceProvider onlyMakerOrMarket(_market) {
        (,uint256 positionId) = IMarket(_market).priceToOpen(id, price, indexPrice, indexPriceTimestamp);
        emit Open(_market, positionId, id);
    }

    /// @notice  add margin to a position
    /// @param _market  market contract address
    /// @param _id  position id
    /// @param _value   assets value to be added
    function depositMargin(address _market, uint256 _id, uint256 _value) external onlyMakerOrMarket(_market) {
        require(_value > 0, "Router: wrong value for add margin");
        Types.Position memory position = getPosition(_market, _id);
        require(position.taker == msg.sender, "Router: caller is not owner");
        require(position.amount > 0, "Router: position not exist");

        IMarket(_market).depositMargin(msg.sender, _id, _value);
        emit DepositMargin(_market, _id);
    }

    function priceToCancel(address _market, uint256 id) external onlyPriceProvider onlyMakerOrMarket(_market) {
        IMarket(_market).cancel(id);
        emit Cancel(_market, id);
    }

    function resetOrderStatusToFail(address _market, uint256 id) external onlyPriceProvider onlyMakerOrMarket(_market) {
        IMarket(_market).resetStatusToFail(id);
        emit ChangeStatus(_market, id);
    }

    /// @notcie centralized oracle liquidate/stop-loss/take-profit positions that should be ended
    /// @param _market  market contract address
    /// @param id   position id
    /// @param price    price for the liquidation order
    /// @param indexPrice   current index price
    /// @param indexPriceTimestamp  timestamp
    /// @param action   reason and how to end the position
    function priceToLiquidate(
        address _market,
        uint256 id,
        uint256 price,
        uint256 indexPrice,
        uint256 indexPriceTimestamp,
        Types.OrderType action
    ) external onlyPriceProvider onlyMakerOrMarket(_market) {
        uint256 orderId = IMarket(_market).liquidate(Types.LiquidityParams(id, price, indexPrice, indexPriceTimestamp, action));
        emit Liquidate(_market, id, orderId);
    }

    /// @notice user set prices for take-profit and stop-loss
    /// @param _market  market contract address
    /// @param _id  position id
    /// @param _profitPrice take-profit price
    /// @param _stopLossPrice stop-loss price
    function setStopProfitAndLossPrice(address _market, uint256 _id, uint256 _profitPrice, uint256 _stopLossPrice) external {
        Types.Position memory position = getPosition(_market, _id);
        require(position.taker == msg.sender, "Router: not taker");
        require(position.amount > 0, "Router: no position");
        IMarket(_market).setStopProfitAndLossPrice(_id, _profitPrice, _stopLossPrice);
        emit SetStopProfitAndLossPrice(_id, _market, _profitPrice, _stopLossPrice);
    }

    function getOpenOrderIds(address _market, address taker) external view returns (uint256[] memory) {
        return IMarket(_market).getOpenOrderIds(taker);
    }

    function getOpenOrder(address _market, uint256 id) public view returns (Types.Order memory) {
        return IMarket(_market).getOpenOrder(id);
    }

    function getPositionId(address _market, address _taker) external view returns (Types.Position memory) {
        uint id = IMarket(_market).getPositionId(_taker);
        return IMarket(_market).getPosition(id);
    }

    function getPosition(address _market, uint256 id) public view returns (Types.Position memory) {
        return IMarket(_market).getPosition(id);
    }

    /// @notice user add liquidity to the pool
    /// @param _makerAddress    pool address
    /// @param _amount  amount to be added
    /// @param _deadline    expire timestamp
    function addLiquidity(address _makerAddress, uint _amount, uint _deadline) external ensure(_deadline) onlyMakerOrMarket(_makerAddress) returns (bool){
        (uint _id, address _maker, uint _value, uint _cancelDeadline) = IMaker(_makerAddress).addLiquidity(msg.sender, _amount);
        emit AddLiquidity(_id, _maker, _value, _cancelDeadline);
        return true;
    }

    function cancelAddLiquidity(address _makerAddress, uint _id) external onlyMakerOrMarket(_makerAddress) returns (uint _amount){
        (_amount) = IMaker(_makerAddress).cancelAddLiquidity(msg.sender, _id);
        emit CancelAddLiquidity(_id, _makerAddress);
    }

    function priceToAddLiquidity(address _makerAddress, uint256 _id, uint256 _price, uint256 _priceTimestamp) external onlyPriceProvider onlyMakerOrMarket(_makerAddress) returns (uint _liquidity){
        (_liquidity) = IMaker(_makerAddress).priceToAddLiquidity(_id, _price, _priceTimestamp);
        emit PriceToAddLiquidity(_id, _makerAddress);
    }

    /// @notice user remove liquidity from a pool
    /// @param _makerAddress    pool address
    /// @param _liquidity   liquidity to be removed
    /// @param _deadline    expire timestamp
    function removeLiquidity(address _makerAddress, uint _liquidity, uint _deadline) external ensure(_deadline) onlyMakerOrMarket(_makerAddress) returns (bool){
        (uint _id, address _maker, uint _value,uint _cancelDeadline) = IMaker(_makerAddress).removeLiquidity(msg.sender, _liquidity);
        emit RemoveLiquidity(_id, _maker, _value, _cancelDeadline);
        return true;
    }

    function priceToRemoveLiquidity(address _makerAddress, uint _id, uint _price, uint _priceTimestamp) external onlyPriceProvider onlyMakerOrMarket(_makerAddress) returns (uint _amount){
        (_amount) = IMaker(_makerAddress).priceToRemoveLiquidity(_id, _price, _priceTimestamp);
        emit PriceToRemoveLiquidity(_id, _makerAddress);
    }

    function cancelRemoveLiquidity(address _makerAddress, uint _id) external onlyMakerOrMarket(_makerAddress) returns (bool){
        IMaker(_makerAddress).cancelRemoveLiquidity(msg.sender, _id);
        emit CancelRemoveLiquidity(_id, _makerAddress);
        return true;
    }

    function systemCancelAddLiquidity(address _makerAddress, uint _id) external onlyPriceProvider onlyMakerOrMarket(_makerAddress) {
        IMaker(_makerAddress).systemCancelAddLiquidity(_id);
    }

    function systemCancelRemoveLiquidity(address _makerAddress, uint _id) external onlyPriceProvider onlyMakerOrMarket(_makerAddress) {
        IMaker(_makerAddress).systemCancelRemoveLiquidity(_id);
    }

    function getMakerOrderIds(address _makerAddress, address _taker) external view returns (uint[] memory _orderIds){
        (_orderIds) = IMaker(_makerAddress).getMakerOrderIds(_taker);
    }

    function getPoolOrder(address _makerAddress, uint _no) external view returns (Types.MakerOrder memory){
        return IMaker(_makerAddress).getOrder(_no);
    }

    function getLpBalanceOf(address _makerAddress, address _taker) external view returns (uint _liquidity, uint _totalSupply){
        (_liquidity, _totalSupply) = IMaker(_makerAddress).getLpBalanceOf(_taker);
    }

    function canOpen(address _makerAddress, uint _makerMargin) external view returns (bool){
        return IMaker(_makerAddress).canOpen(_makerMargin);
    }

    function canRemoveLiquidity(address _makerAddress, uint _price, uint _liquidity) external view returns (bool){
        return IMaker(_makerAddress).canRemoveLiquidity(_price, _liquidity);
    }

    function canAddLiquidity(address _makerAddress, uint _price) external view returns (bool){
        return IMaker(_makerAddress).canAddLiquidity(_price);
    }

    function getFundingInfo(uint256 id, address maker, address market, uint256 indexPrice) external view returns (int256 frX96, int256 fgX96, int256 fLastX96){
        fgX96 = IMarket(market).fundingGrowthGlobalX96();
        Types.Position memory position = IMarket(market).getPosition(id);
        Types.FundingResponse memory response = calc.getFunding(Types.FundingParams(manager, maker, position, indexPrice));
        frX96 = response._fundingGrowthGlobalX96;
        fLastX96 = position.frLastX96;
    }
}

