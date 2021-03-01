pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract pptBar is ERC20("PPTBar", "xPPT"){
    using SafeMath for uint256;
    IERC20 public ppt;

    constructor(IERC20 _ppt) public {
        ppt = _ppt;
    }

    // Enter the bar. Pay some ppts. Earn some shares.
    function enter(uint256 _amount) public {
        uint256 totalppt = ppt.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || totalppt == 0) {
            _mint(msg.sender, _amount);
        } else {
            uint256 what = _amount.mul(totalShares).div(totalppt);
            _mint(msg.sender, what);
        }
        ppt.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the bar. Claim back your ppts.
    function leave(uint256 _share) public {
        uint256 totalShares = totalSupply();
        uint256 what = _share.mul(ppt.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        ppt.transfer(msg.sender, what);
    }
}