pragma solidity ^0.6.12;

interface ERC677Receiver {
  function onTokenTransfer(address _sender, uint _value, bytes memory _data) external;
}