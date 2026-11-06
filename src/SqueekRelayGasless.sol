// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Squeek Relay Gasless
/// @notice Player actions are EIP-712 authorizations; the keeper pays gas.
contract SqueekRelayGasless {
    uint8 public constant SPRINT = 0;
    uint8 public constant DRAFT = 1;
    uint8 public constant SLEEPER = 2;
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant JOIN_TYPEHASH = keccak256("Join(address player,uint256 roundId,uint8 strategy,uint256 nonce,uint256 deadline)");
    bytes32 private constant CASHOUT_TYPEHASH = keccak256("CashOut(address player,uint256 roundId,uint256 nonce,uint256 deadline)");

    address public immutable deployer;
    address public keeper;
    bytes32 public immutable DOMAIN_SEPARATOR;
    uint256 public currentRound;
    mapping(address => uint256) public joinNonces;
    mapping(address => uint256) public cashoutNonces;

    struct Round { uint64 openedAt; uint64 closedAt; bool open; }
    struct Position { uint64 joinedAt; uint8 strategy; bool joined; bool cashedOut; uint256 score; }
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => Position)) public positions;
    mapping(address => uint256) public lifetimeScore;

    event RoundOpened(uint256 indexed roundId, uint256 openedAt);
    event RoundClosed(uint256 indexed roundId, uint256 closedAt);
    event Joined(uint256 indexed roundId, address indexed player, uint8 strategy, uint256 joinedAt);
    event CashedOut(uint256 indexed roundId, address indexed player, uint256 score);

    error NotKeeper(); error InvalidRound(); error RoundNotOpen(); error RoundAlreadyOpen();
    error AlreadyJoined(); error NotJoined(); error AlreadyCashedOut(); error InvalidStrategy(); error SignatureInvalid(); error Expired();

    constructor(address initialKeeper) {
        deployer = msg.sender;
        keeper = initialKeeper == address(0) ? msg.sender : initialKeeper;
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Squeek Relay"), keccak256("1"), block.chainid, address(this)));
    }
    modifier onlyKeeper() { if (msg.sender != keeper) revert NotKeeper(); _; }
    function setKeeper(address next) external { if (msg.sender != deployer) revert NotKeeper(); keeper = next; }
    function openRound(uint256 id) external onlyKeeper { if (id == 0 || id <= currentRound) revert InvalidRound(); if (rounds[id].open) revert RoundAlreadyOpen(); rounds[id] = Round(uint64(block.timestamp), 0, true); currentRound = id; emit RoundOpened(id, block.timestamp); }
    function closeRound(uint256 id) external onlyKeeper { if (!rounds[id].open) revert RoundNotOpen(); rounds[id].closedAt = uint64(block.timestamp); rounds[id].open = false; emit RoundClosed(id, block.timestamp); }

    function joinFor(address player, uint256 roundId, uint8 strategy, uint256 deadline, bytes calldata signature) external onlyKeeper {
        if (block.timestamp > deadline) revert Expired();
        uint256 nonce = joinNonces[player]++;
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(JOIN_TYPEHASH, player, roundId, strategy, nonce, deadline))));
        if (_recover(digest, signature) != player) revert SignatureInvalid();
        _join(player, roundId, strategy);
    }

    function cashOutFor(address player, uint256 roundId, uint256 deadline, bytes calldata signature) external onlyKeeper returns (uint256 score) {
        if (block.timestamp > deadline) revert Expired();
        uint256 nonce = cashoutNonces[player]++;
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(CASHOUT_TYPEHASH, player, roundId, nonce, deadline))));
        if (_recover(digest, signature) != player) revert SignatureInvalid();
        Position storage p = positions[roundId][player];
        if (!p.joined) revert NotJoined(); if (p.cashedOut) revert AlreadyCashedOut(); if (!rounds[roundId].open) revert RoundNotOpen();
        uint256 elapsed = block.timestamp - uint256(p.joinedAt); uint256 bps = 10_000 + _paceBps(p.strategy) * elapsed; if (bps > 60_000) bps = 60_000;
        score = (100 * bps) / 10_000; p.cashedOut = true; p.score = score; lifetimeScore[player] += score; emit CashedOut(roundId, player, score);
    }

    function _join(address player, uint256 roundId, uint8 strategy) private {
        if (!rounds[roundId].open) revert RoundNotOpen(); if (strategy > SLEEPER) revert InvalidStrategy(); Position storage p = positions[roundId][player]; if (p.joined) revert AlreadyJoined();
        p.joinedAt = uint64(block.timestamp); p.strategy = strategy; p.joined = true; emit Joined(roundId, player, strategy, block.timestamp);
    }
    function _paceBps(uint8 strategy) private pure returns (uint256) { if (strategy == SPRINT) return 320; if (strategy == DRAFT) return 240; if (strategy == SLEEPER) return 180; revert InvalidStrategy(); }
    function _recover(bytes32 digest, bytes calldata signature) private pure returns (address) { if (signature.length != 65) revert SignatureInvalid(); bytes32 r; bytes32 s; uint8 v; assembly { r := calldataload(signature.offset) s := calldataload(add(signature.offset, 32)) v := byte(0, calldataload(add(signature.offset, 64))) } if (v < 27) v += 27; return ecrecover(digest, v, r, s); }
}
