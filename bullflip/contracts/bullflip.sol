// SPDX-License-Identifier: MIT
// File: @openzeppelin/contracts/utils/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.17;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// File: @thirdweb-dev/contracts/eip/interface/IERC20.sol


pragma solidity ^0.8.0;

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// File: contracts/BullFlip.sol


pragma solidity ^0.8.0;



// Base contract with the desired fallback behavior
contract BaseContract {
    fallback() external {
        revert("Fallback function not allowed");
    }

    receive() external payable {
        revert("Receive function not allowed");
    }
}

contract BullFlip is BaseContract, ReentrancyGuard {
    enum BetOption { BULLS, BEARS }
    enum SupportedToken { MY_TOKEN }

    struct Bet {
        address payable bettor;
        uint256 amount;
        BetOption betOption;
    }

    address public owner;
    uint256 public houseFeePercentage = 3;
    SupportedToken[] public supportedTokens;
    mapping(address => mapping(SupportedToken => uint256[])) public validBetAmounts;
    mapping(address => uint256) public balances;
    Bet[] public bets;

    event BetPlaced(address indexed bettor, uint256 amount, BetOption betOption);
    event BetResolved(address indexed bettor, uint256 amount, BetOption betOption, bool won);
    event HouseFeeApplied(address indexed bettor, uint256 amount);

    bool public isPaused;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    constructor() {
        owner = msg.sender;
        supportedTokens.push(SupportedToken.MY_TOKEN);
        validBetAmounts[0xC1B6844D5134c8E550043f01FFbF49CA66Efc77F][SupportedToken.MY_TOKEN] = [1, 5, 10, 25, 100, 500, 1000, 10000, 25000]; // Default bet amounts for MY_TOKEN
    }

    function addSupportedToken(SupportedToken token) external onlyOwner {
        require(!isTokenSupported(token), "Token already supported");
        supportedTokens.push(token);
        if (token == SupportedToken.MY_TOKEN) {
            validBetAmounts[0xC1B6844D5134c8E550043f01FFbF49CA66Efc77F][SupportedToken.MY_TOKEN] = [1, 5, 10, 25, 100, 500, 1000, 10000, 25000]; // Set default bet amounts
        }
    }

    function fundContract(SupportedToken token, uint256 amount) external onlyOwner {
        require(isTokenSupported(token), "Token not supported");
        IERC20(_getTokenAddress(token)).transferFrom(msg.sender, address(this), amount);
        balances[_getTokenAddress(token)] += amount;
    }

    function setHouseFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Fee percentage must be 100 or less");
        houseFeePercentage = newFee;
    }

    function placeBet(SupportedToken token, uint256 amount, BetOption betOption) external whenNotPaused nonReentrant {
        require(isTokenSupported(token), "Token not supported");
        require(_isValidBetAmount(token, amount), "Invalid bet amount");
        require(balances[_getTokenAddress(token)] >= amount, "Insufficient balance");

        uint256 houseCut = (amount * houseFeePercentage) / 100;
        uint256 betValue = amount - houseCut;

        IERC20(_getTokenAddress(token)).transferFrom(msg.sender, address(this), amount);
        balances[_getTokenAddress(token)] += betValue;

        Bet memory newBet = Bet({
            bettor: payable(msg.sender),
            amount: betValue,
            betOption: betOption
        });

        bets.push(newBet);

        emit BetPlaced(msg.sender, betValue, betOption);
        emit HouseFeeApplied(msg.sender, houseCut);
    }

    function resolveBet(uint256 betIndex) external whenNotPaused nonReentrant {
        require(betIndex < bets.length, "Invalid bet index");
        Bet storage bet = bets[betIndex];
        require(msg.sender == bet.bettor, "You are not the bettor");

        BetOption flipResult = BetOption(_getRandomResult() % 2);

        bool won = bet.betOption == flipResult;
        if (won) {
            uint256 payout = bet.amount * 2;
            IERC20(_getTokenAddress(SupportedToken.MY_TOKEN)).transfer(bet.bettor, payout);
            balances[_getTokenAddress(SupportedToken.MY_TOKEN)] -= payout;
        } else {
            balances[_getTokenAddress(SupportedToken.MY_TOKEN)] += bet.amount;
        }

        emit BetResolved(bet.bettor, bet.amount, bet.betOption, won);

        // Delete the bet by swapping with the last bet and then pop the last bet
        uint256 lastIndex = bets.length - 1;
        if (betIndex != lastIndex) {
            bets[betIndex] = bets[lastIndex];
        }
        bets.pop();
    }

    function withdrawTokens(SupportedToken token, uint256 amount) external onlyOwner {
        require(isTokenSupported(token), "Token not supported");
        require(amount <= balances[_getTokenAddress(token)], "Insufficient balance");

        IERC20(_getTokenAddress(token)).transfer(owner, amount);
        balances[_getTokenAddress(token)] -= amount;
    }

    function getRandomResult() external view whenNotPaused returns (uint256) {
        // Use blockhash of the previous block as a simple randomness source
        return _getRandomResult();
    }

    function pauseContract() external onlyOwner {
        isPaused = true;
    }

    function unpauseContract() external onlyOwner {
        isPaused = false;
    }

    function isTokenSupported(SupportedToken token) public view returns (bool) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function setValidBetAmounts(SupportedToken token, uint256[] memory amounts) external onlyOwner {
        require(isTokenSupported(token), "Token not supported");
        validBetAmounts[0xC1B6844D5134c8E550043f01FFbF49CA66Efc77F][token] = amounts;
    }

    // Function to check if a given amount is a valid bet amount for a specific token
    function _isValidBetAmount(SupportedToken token, uint256 amount) internal view returns (bool) {
        uint256[] memory validAmounts = validBetAmounts[0xC1B6844D5134c8E550043f01FFbF49CA66Efc77F][token];
        for (uint256 i = 0; i < validAmounts.length; i++) {
            if (amount == validAmounts[i]) {
                return true;
            }
        }
        return false;
    }

    function _getTokenAddress(SupportedToken token) internal pure returns (address) {
        if (token == SupportedToken.MY_TOKEN) {
            return 0xC1B6844D5134c8E550043f01FFbF49CA66Efc77F;
        }
        revert("Unsupported token");
    }

    function _getRandomResult() internal view returns (uint256) {
        // Use blockhash of the previous block as a simple randomness source
        return uint256(blockhash(block.number - 1));
    }
}
