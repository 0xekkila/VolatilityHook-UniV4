pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

contract BaseChallenge is Test {
    address me = 0xb6baBAc081240467d83df35811B4EbD224b3FA28;
    uint256 timestamp = 1731928468;
    uint256 blockNumber = 18101690;

    function setUp() public {}

    function testBase() public {
        bytes32 answer = (bytes32(keccak256(abi.encode(22))));
        console.logBytes32(answer);
    }

    function testPassword() public {
        uint256 randomNonce = uint256(keccak256(abi.encodePacked(timestamp, me))) % 10000;
        console.log("randomNonce", randomNonce);
        bytes32 answer = keccak256(abi.encodePacked(blockhash(18101690 - 1), me, timestamp, randomNonce));
        console.logBytes32(answer);
    }
}
