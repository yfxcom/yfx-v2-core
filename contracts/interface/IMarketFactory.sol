// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

interface IMarketFactory {
    function createMarket(address manager) external returns (address);
}
