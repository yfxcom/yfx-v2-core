// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

interface IWrappedCoin {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
