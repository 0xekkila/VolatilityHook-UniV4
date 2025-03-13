// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IVault {
    function unlock(bytes32 password) external;

    function locked() external view returns (bool);
}

contract BaseScript is Script {
    address deployer;
    address vault = 0xc9c4bdcfCF96fb2c1111e147ac83EEb504c4E9B9;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployer);

        IVault(vault).unlock(0x64df0ae5562ff0ffdda64190c6c108c5a8293bc6ff620d5548dd2541fe491ffd);
        console.log(IVault(vault).locked());
    }
}
