// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import "./Market.sol";

contract MarketFactory {
    event CreateMarket(address market);

    function createMarket(address manager, address _calc) external returns (address){
        Market market = new Market(manager, _calc);
        emit CreateMarket(address(market));
        return address(market);
    }
}
