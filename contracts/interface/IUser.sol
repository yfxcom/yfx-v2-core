// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

interface IUser{
    function totalSupply(address token) external view returns (uint256);
    function balance(address token, address owner) external view returns (uint256);

    function deposit(uint8 coinType, address token, uint256 value) external payable;
    function withdraw(uint8 coinType, address token, uint256 value) external;

    function transfer(address token, address fromUser, uint256 value) external returns (bool);
    function receiveToken(address token, address toUser, uint256 value) external returns (bool);
}
