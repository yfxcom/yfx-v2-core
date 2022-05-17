pragma solidity >=0.6.0 <0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Faucet {
    mapping(address => mapping(address => uint256)) public waitTime;

    function claim(address token, address to) external {
        require(block.number >= waitTime[to][token], "wait one day");
        waitTime[to][token] = block.number + 30000;
        IERC20(token).transfer(to, 10000000000000000000000);
    }
}
