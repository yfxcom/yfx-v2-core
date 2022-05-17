// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import "./Maker.sol";

contract MakerFactory {
    event CreateMaker(address maker);

    function createMaker(address manager) external returns (address){
        Maker maker = new Maker(manager);
        emit CreateMaker(address(maker));
        return address(maker);
    }
}
