// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SqueekRelay} from "../src/SqueekRelay.sol";

contract SqueekRelayTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SqueekRelay relay;
    address player = address(0xBEEF);

    function setUp() public {
        relay = new SqueekRelay(address(this));
    }

    function testJoinAndCashOutStoresReceipt() public {
        relay.openRound(255);
        uint8 strategy = relay.DRAFT();
        vm.prank(player);
        relay.join(255, strategy);
        vm.prank(player);
        uint256 score = relay.cashOut(255);
        require(score == 100, "base score mismatch");
        (, , , bool cashedOut, uint256 stored) = relay.positions(255, player);
        require(cashedOut && stored == 100, "receipt missing");
    }

    function testCannotJoinClosedRound() public {
        relay.openRound(256);
        relay.closeRound(256);
        (bool ok,) = address(relay).call(abi.encodeWithSelector(relay.join.selector, 256, relay.SPRINT()));
        require(!ok, "closed round accepted join");
    }

}

interface Vm { function prank(address sender) external; }
