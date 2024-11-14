// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { WDYT } from "src/wdyt.sol";
import { MockUSDB } from "test/mock/MockUSDB.sol";


contract Deploy is Script {
    address admin = 0xc11d7d134c432209aBFa6780cE8aF833FB413476;

    WDYT wdyt;
    ERC1967Factory factory = ERC1967Factory(0x2fCfE8dFdA840ca42a5458630ce3f348e29034Db);

    MockUSDB usdb;


    function run() public {
        uint256 key = vm.envUint("KEY");

        vm.startBroadcast(key);
        _deploy();
        vm.stopBroadcast();

        console.log("WDYT", address(wdyt));
        console.log("USDB", address(usdb));
        console.log("Factory", address(factory));
    }

    function _deploy() internal {
        usdb = new MockUSDB();
        address wdyt_logic = address(new WDYT({
            usdb_: address(usdb)
        }));

        wdyt = WDYT(
            factory.deployAndCall(
                wdyt_logic, 
                admin,
                abi.encodeCall(WDYT.initialize, (admin))
            )
        );
    }
}