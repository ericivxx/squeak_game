// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Squeek Relay
/// @notice Non-custodial, testnet-only relay rounds. No funds are accepted.
/// @dev A keeper mirrors the public Squeekchain wheel telemetry by opening and
///      closing the matching onchain round. Player score receipts are permanent.
contract SqueekRelay {
    uint8 public constant SPRINT = 0;
    uint8 public constant DRAFT = 1;
    uint8 public constant SLEEPER = 2;
    uint256 public constant MAX_ROUND_SECONDS = 7 days;

    address public immutable deployer;
    address public keeper;
    uint256 public currentRound;

    struct Round {
        uint64 openedAt;
        uint64 closedAt;
        bool open;
    }

    struct Position {
        uint64 joinedAt;
        uint8 strategy;
        bool joined;
        bool cashedOut;
        uint256 score;
    }

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => Position)) public positions;
    mapping(address => uint256) public lifetimeScore;

    event KeeperUpdated(address indexed previousKeeper, address indexed newKeeper);
    event RoundOpened(uint256 indexed roundId, uint256 openedAt);
    event RoundClosed(uint256 indexed roundId, uint256 closedAt);
    event Joined(uint256 indexed roundId, address indexed player, uint8 strategy, uint256 joinedAt);
    event CashedOut(uint256 indexed roundId, address indexed player, uint8 strategy, uint256 elapsedSeconds, uint256 multiplierBps, uint256 score);

    error NotKeeper();
    error InvalidRound();
    error RoundNotOpen();
    error RoundAlreadyOpen();
    error AlreadyJoined();
    error NotJoined();
    error AlreadyCashedOut();
    error InvalidStrategy();
    error RoundExpired();

    constructor(address initialKeeper) {
        deployer = msg.sender;
        keeper = initialKeeper == address(0) ? msg.sender : initialKeeper;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper();
        _;
    }

    function setKeeper(address newKeeper) external {
        if (msg.sender != deployer) revert NotKeeper();
        if (newKeeper == address(0)) revert InvalidRound();
        emit KeeperUpdated(keeper, newKeeper);
        keeper = newKeeper;
    }

    function openRound(uint256 roundId) external onlyKeeper {
        if (roundId == 0 || roundId <= currentRound) revert InvalidRound();
        Round storage round = rounds[roundId];
        if (round.open) revert RoundAlreadyOpen();
        round.openedAt = uint64(block.timestamp);
        round.closedAt = 0;
        round.open = true;
        currentRound = roundId;
        emit RoundOpened(roundId, block.timestamp);
    }

    function closeRound(uint256 roundId) external onlyKeeper {
        Round storage round = rounds[roundId];
        if (!round.open) revert RoundNotOpen();
        round.closedAt = uint64(block.timestamp);
        round.open = false;
        emit RoundClosed(roundId, block.timestamp);
    }

    function join(uint256 roundId, uint8 strategy) external {
        Round storage round = rounds[roundId];
        if (!round.open) revert RoundNotOpen();
        if (block.timestamp > uint256(round.openedAt) + MAX_ROUND_SECONDS) revert RoundExpired();
        if (strategy > SLEEPER) revert InvalidStrategy();
        Position storage position = positions[roundId][msg.sender];
        if (position.joined) revert AlreadyJoined();
        position.joinedAt = uint64(block.timestamp);
        position.strategy = strategy;
        position.joined = true;
        emit Joined(roundId, msg.sender, strategy, block.timestamp);
    }

    function cashOut(uint256 roundId) external returns (uint256 score) {
        Round storage round = rounds[roundId];
        Position storage position = positions[roundId][msg.sender];
        if (!position.joined) revert NotJoined();
        if (position.cashedOut) revert AlreadyCashedOut();
        if (!round.open) revert RoundNotOpen();

        uint256 elapsed = block.timestamp - uint256(position.joinedAt);
        uint256 multiplierBps = 10_000 + _paceBps(position.strategy) * elapsed;
        if (multiplierBps > 60_000) multiplierBps = 60_000;
        score = (100 * multiplierBps) / 10_000;
        position.cashedOut = true;
        position.score = score;
        lifetimeScore[msg.sender] += score;
        emit CashedOut(roundId, msg.sender, position.strategy, elapsed, multiplierBps, score);
    }

    function _paceBps(uint8 strategy) private pure returns (uint256) {
        if (strategy == SPRINT) return 320;
        if (strategy == DRAFT) return 240;
        if (strategy == SLEEPER) return 180;
        revert InvalidStrategy();
    }
}
