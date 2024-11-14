// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

contract WDYT is OwnableRoles, Initializable {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketCreated(uint256 indexed id, uint256 indexed telegram, bytes description, uint256 deadline);
    event BetMade(uint256 indexed id, address indexed bettor, bool indexed outcome, uint256 amount, uint256 shares);
    event MarketResolved(uint256 indexed id, bool indexed outcome);
    event BetRedeemed(uint256 indexed id, address indexed bettor, uint256 payout);

    /*//////////////////////////////////////////////////////////////
                               INITIALIZE
    //////////////////////////////////////////////////////////////*/

    constructor(address usdb_) {
        usdb = usdb_;
        _disableInitializers();
    }

    function initialize(address owner_) public initializer {
        _initializeOwner(owner_);
    }

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    modifier Admin {
        require(msg.sender == owner() || hasAllRoles(msg.sender, ADMIN_ROLE), "NOT_ADMIN");
        _;
    }

    modifier Resolver {
        require(msg.sender == owner() || hasAllRoles(msg.sender, RESOLVER_ROLE), "NOT_RESOLVER");
        _;
    }

    struct Market {
        bytes description;
        uint256 deadline;
        mapping(bool bet => uint256 shares) totalShares;
        mapping(address bettor => mapping(bool bet => uint256)) shares;
        mapping(address bettor => mapping(bool bet => uint256)) bets;
        mapping(bool bet => uint256 assets) totalAssets;
        bool resolved;
        bool outcome;
    }

    struct MarketData {
        bytes description;
        uint256 deadline;
        uint256 totalYesShares;
        uint256 totalNoShares;
        uint256 yesBets;
        uint256 noBets;
        bool resolved;
        bool outcome;
    }

    struct BetData {
        uint256 yesShares;
        uint256 noShares;
        uint256 yesBets;
        uint256 noBets;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 constant public ADMIN_ROLE = _ROLE_1;
    uint256 constant public RESOLVER_ROLE = _ROLE_2;

    uint256 public constant basePrice = 1e16;           // Starting price (0.01 ether) | change with different asset decimals
    uint256 public constant invariant = .0000008 ether;           

    address immutable public usdb;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 id => Market market) internal _market;

    uint256 internal _counter;

    /*//////////////////////////////////////////////////////////////
                        MARKET CREATE + RESOLVE
    //////////////////////////////////////////////////////////////*/

    function createMarket(
        bytes calldata description, 
        uint256 telegram,
        uint256 deadline
    ) external onlyOwner returns (uint256 id) {
        id = ++_counter;

        require(description.length > 0, "EMPTY_DESCRIPTION");
        require(deadline > block.timestamp, "INVALID_DEADLINE");

        Market storage market = _market[id];

        market.description = description;
        market.deadline = deadline;

        emit MarketCreated({
            id: id,
            telegram: telegram,
            description: description,
            deadline: deadline
        });
    }

    function resolveMarket(uint256 id, bool outcome) external Resolver {
        Market storage market = _market[id];

        require(market.deadline > 0, "MARKET_DOES_NOT_EXIST");
        require(!market.resolved, "MARKET_ALREADY_RESOLVED");
        require(market.deadline <= block.timestamp, "DEADLINE_NOT_PASSED");

        market.resolved = true;
        market.outcome = outcome;

        emit MarketResolved(id, outcome);
    }

    /*//////////////////////////////////////////////////////////////
                                  BET
    //////////////////////////////////////////////////////////////*/

    function bet(
        uint256 id, 
        bool outcome, 
        uint256 amount
    ) external returns (uint256 shares) {
        return _bet({
            id: id,
            bettor: msg.sender,
            outcome: outcome,
            amount: amount
        });
    }

    function betFor(
        uint256 id, 
        address bettor, 
        bool outcome, 
        uint256 amount
    ) external Admin returns (uint256 shares) {
        return _bet({
            id: id,
            bettor: bettor,
            outcome: outcome,
            amount: amount
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 REDEEM
    //////////////////////////////////////////////////////////////*/

    function redeem(uint256 id, address bettor) external returns (uint256 payout) {
        Market storage market = _market[id];

        require(market.deadline > 0, "MARKET_DOES_NOT_EXIST");
        require(market.resolved, "MARKET_NOT_RESOLVED");

        uint stake = market.bets[bettor][market.outcome];
        uint shares = market.shares[bettor][market.outcome]; 

        require(shares > 0, "NO_WINNING_SHARES");

        payout = (shares * market.totalAssets[!market.outcome] ) / market.totalShares[market.outcome];

        market.totalShares[market.outcome] -= shares;
        market.totalAssets[!market.outcome] -= payout;
        delete market.bets[bettor][market.outcome];
        delete market.shares[bettor][market.outcome];

        usdb.safeTransfer(bettor, payout + stake);

        emit BetRedeemed(id, bettor, payout + stake);
    }

    /// note: non-permissioned is fine
    function redeemBatch(uint256 id, address[] calldata bettors) external {
        Market storage market = _market[id];

        require(market.deadline > 0, "MARKET_DOES_NOT_EXIST");
        require(market.resolved, "MARKET_NOT_RESOLVED");

        uint totalShares = market.totalShares[market.outcome];
        uint totalAssets = market.totalAssets[!market.outcome];

        uint length = bettors.length;

        address bettor; uint stake; uint shares; uint payout;

        for (uint i; i < length; ++i) {
            bettor = bettors[i];
            stake = market.bets[bettor][market.outcome];
            shares = market.shares[bettor][market.outcome];

            if (shares == 0) continue;

            payout = (shares * totalAssets) / totalShares;

            totalShares -= shares;
            totalAssets -= payout;
            delete market.bets[bettor][market.outcome];
            delete market.shares[bettor][market.outcome];

            usdb.safeTransfer(bettor, payout + stake);

            emit BetRedeemed(id, bettor, payout + stake);
        }

        market.totalShares[market.outcome] = totalShares;
        market.totalAssets[!market.outcome] = totalAssets;
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function setAdmin(address admin) external onlyOwner {
        _grantRoles(admin, ADMIN_ROLE);
    }

    function setResolver(address resolver) external onlyOwner {
        _grantRoles(resolver, RESOLVER_ROLE);
    }

    function removeAdmin(address admin) external onlyOwner {
        _removeRoles(admin, ADMIN_ROLE);
    }

    function removeResolver(address resolver) external onlyOwner {
        _removeRoles(resolver, RESOLVER_ROLE);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getMarket(uint256 id) external view returns (MarketData memory) {
        Market storage market = _market[id];

        return MarketData({
            description: market.description,
            deadline: market.deadline,
            totalYesShares: market.totalShares[true],
            totalNoShares: market.totalShares[false],
            yesBets: market.totalAssets[true],
            noBets: market.totalAssets[false],
            resolved: market.resolved,
            outcome: market.outcome
        });
    }

    function getBet(uint256 id, address bettor) external view returns (BetData memory) {
        Market storage market = _market[id];

        return BetData({
            yesShares: market.shares[bettor][true],
            noShares: market.shares[bettor][false],
            yesBets: market.bets[bettor][true],
            noBets: market.bets[bettor][false]
        });
    }

    function calcShares(
        uint256 id,
        bool outcome,
        uint256 assets
    ) external view returns (uint256 shares) {
        Market storage market = _market[id];

        return _calcShares({
            assets: assets,
            supply: market.totalShares[outcome]
        });
    }

    function calcPayout(uint256 id, bool outcome, uint256 stake) external view returns (uint256 payout) {
        Market storage market = _market[id];

        require(market.deadline > 0, "MARKET_DOES_NOT_EXIST");

        uint shares = _calcShares({
            assets: stake,
            supply: market.totalShares[outcome]
        });

        return shares * market.totalAssets[!outcome] / (market.totalShares[outcome] + shares);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _bet(uint256 id, address bettor, bool outcome, uint256 amount) internal returns (uint256 shares) {
        usdb.safeTransferFrom({
            from: bettor,
            to: address(this),
            amount: amount
        });

        Market storage market = _market[id];

        require(market.deadline > 0, "MARKET_DOES_NOT_EXIST");
        require(market.deadline > block.timestamp, "MARKET_CLOSED");

        shares = _calcShares({
            assets: amount,
            supply: market.totalShares[outcome]
        });

        require(shares > 0, "ZERO_SHARES");
        
        market.totalShares[outcome] += shares;
        market.bets[bettor][outcome] += amount;
        market.shares[bettor][outcome] += shares;
        market.totalAssets[outcome] += amount;

        emit BetMade({
            id: id,
            bettor: bettor,
            outcome: outcome,
            amount: amount,
            shares: shares
        });
    }

    function _calcShares(uint256 assets, uint256 supply) internal pure returns (uint256 shares) {
        uint256 a = invariant / 2;
        uint256 b = basePrice + (invariant * supply) - a;

        uint256 discriminant = (b * b) + (4 * a * assets);
        uint256 sqrtDiscriminant = discriminant.sqrt();

        shares = (sqrtDiscriminant - b) / (2 * a);
    }
}