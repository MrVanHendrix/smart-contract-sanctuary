pragma solidity 0.6.12;
contract Random {
    uint public blockNumber;
    bytes32 public blockHashNow;
    bytes32 public blockHashPrevious;
uint256 public seed ;
uint256 public roll;
bytes32 public ret;
 bytes public kk;
    function setValues() public {
        blockNumber = 10656321;
        //blockHashNow = block.blockhash(blockNumber);
        //blockHashPrevious = blockhash(blockNumber - 1);
        kk = abi.encodePacked(blockhash(blockNumber - 1), '0xc2d243dfd07885f6ff75eb7571c8bfb97e080bc9');
        ret = keccak256(kk);
        seed = uint256(ret);
	    roll = seed % 100;
    }    
}

{
  "optimizer": {
    "enabled": true,
    "runs": 1
  },
  "evmVersion": "istanbul",
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "metadata": {
    "useLiteralContent": true
  },
  "libraries": {}
}