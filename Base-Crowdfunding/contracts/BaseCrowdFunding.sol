// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/eip/interface/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Base contract with the desired fallback behavior
contract BaseContract {
    fallback() external {
        revert("Fallback function not allowed");
    }

    receive() external payable {
        revert("Receive function not allowed");
    }
}

contract BullBearCow is BaseContract, ReentrancyGuard {
    enum BetOption { BULLS, BEARS, COWS }
    enum SupportedToken { MY_TOKEN }

    struct Bet {
        address payable bettor;
        uint256 amount;
        BetOption betOption;
    }

    address public owner;
    uint256 public houseFeePercentage = 3;
    SupportedToken[] public supportedTokens;
    mapping(address => uint256[]) public validBetAmounts;
    mapping(address => uint256) public balances;
    Bet[] public bets;

    event BetPlaced(address indexed bettor, uint256 amount, BetOption betOption);
    event BetResolved(address indexed bettor, uint256 amount, BetOption betOption, bool won);

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
        validBetAmounts[0x1D81EC956fb906Ad4c863a68cCCB3831550963c1] = [1, 5, 10, 25, 100, 500, 1000, 10000, 25000]; // Default bet amounts for MY_TOKEN
    }

    function addSupportedToken(SupportedToken token) external onlyOwner {
        require(!isTokenSupported(token), "Token already supported");
        supportedTokens.push(token);
        if (token == SupportedToken.MY_TOKEN) {
            validBetAmounts[0x1D81EC956fb906Ad4c863a68cCCB3831550963c1] = [1, 5, 10, 25, 100, 500, 1000, 10000, 25000]; // Set default bet amounts
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
    }




function resolveBet(uint256 betIndex) external whenNotPaused nonReentrant {
        require(betIndex < bets.length, "Invalid bet index");
        Bet storage bet = bets[betIndex];
        require(msg.sender == bet.bettor, "You are not the bettor");

        BetOption flipResult = BetOption(_getRandomResult() % 3);

        bool won;
        if (bet.betOption == BetOption.BULLS) {
            won = flipResult == BetOption.COWS;
        } else if (bet.betOption == BetOption.BEARS) {
            won = flipResult == BetOption.BULLS;
        } else {
            won = flipResult == BetOption.BEARS;
        }

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
        validBetAmounts[0x1D81EC956fb906Ad4c863a68cCCB3831550963c1] = amounts;
    }

    // Function to check if a given amount is a valid bet amount for a specific token
    function isValidBetAmount(SupportedToken token, uint256 amount) external view returns (bool) {
        require(isTokenSupported(token), "Token not supported");
        uint256[] memory validAmounts = validBetAmounts[0x1D81EC956fb906Ad4c863a68cCCB3831550963c1];
        for (uint256 i = 0; i < validAmounts.length; i++) {
            if (amount == validAmounts[i]) {
                return true;
            }
        }
        return false;
    }

    function _getTokenAddress(SupportedToken token) internal pure returns (address) {
        if (token == SupportedToken.MY_TOKEN) {
            return 0x1D81EC956fb906Ad4c863a68cCCB3831550963c1;
        }
        revert("Unsupported token");
    }

    function _isValidBetAmount(SupportedToken, uint256 amount) internal view returns (bool) {
    uint256[] memory validAmounts = validBetAmounts[0x1D81EC956fb906Ad4c863a68cCCB3831550963c1];
    for (uint256 i = 0; i < validAmounts.length; i++) {
        if (amount == validAmounts[i]) {
            return true;
        }
    }
    return false;
}


    function _getRandomResult() internal view returns (uint256) {
        // Use blockhash of the previous block as a simple randomness source
        return uint256(blockhash(block.number - 1));
    }
}
