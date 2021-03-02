pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract serBar is ERC20("SERBar", "xSER"){
    using SafeMath for uint256;
    IERC20 public ser;

    constructor(IERC20 _ser) public {
        ser = _ser;
    }

    // Enter the bar. Pay some sers. Earn some shares.
    function enter(uint256 _amount) public {
        uint256 totalser = ser.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || totalser == 0) {
            _mint(msg.sender, _amount);
        } else {
            uint256 what = _amount.mul(totalShares).div(totalser);
            _mint(msg.sender, what);
        }
        ser.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the bar. Claim back your sers.
    function leave(uint256 _share) public {
        uint256 totalShares = totalSupply();
        uint256 what = _share.mul(ser.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        ser.transfer(msg.sender, what);
    }
}