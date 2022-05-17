// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import './library/SafeMath.sol';
contract ERC20 {
    using SafeMath for uint;

    string public name = 'YFX V2';
    string public symbol = 'YFX-V2';
    uint public constant decimals = 18;
    uint  public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function _mint(address to, uint value) internal {
        require(to != address(0), "ERC20: mint to the zero address");
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        require(from != address(0), "ERC20: _burn from the zero address");
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) internal {
        require(owner != address(0), "ERC20: owner is the zero address");
        require(spender != address(0), "ERC20: spender is the zero address");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) internal {
        require(from != address(0), "ERC20: _transfer from the zero address");
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        require(from != address(0), "ERC20: transferFrom from the zero address");
        if (allowance[from][msg.sender] != uint(- 1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }
}
