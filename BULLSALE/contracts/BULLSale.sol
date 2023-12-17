// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IUniswapV2Pair {
    function sync() external;
}

contract TokenSale is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 public saleStartTime;
    uint256 public saleEndTime;
    uint256 public saleSupply;
    uint256 public vaultLockDuration = 1314 days;

    address public uniswapPair;
    address public vault;
    bool public saleActive = true;

    mapping(address => uint256) public vestingStart;
    mapping(address => uint256) public vestedAmount;
    mapping(address => bool) public vestingPaused;

    event TokensPurchased(address indexed buyer, uint256 amount);
    event VestingPaused(address indexed account);
    event VestingResumed(address indexed account);
    event VestingAdjusted(address indexed account, uint256 newVestingStart);

    modifier saleActiveOrOwner() {
        require(saleActive || msg.sender == owner(), "Sale is not active");
        _;
    }

    modifier onlyUniswapPair() {
        require(msg.sender == uniswapPair, "Caller is not the Uniswap pair");
        _;
    }

    modifier notPaused(address account) {
        require(!vestingPaused[account], "Vesting is paused for this account");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 _saleSupply,
        uint256 _saleStartTime,
        uint256 _saleEndTime,
        address _uniswapPair,
        address _vault
    ) ERC20(name, symbol) {
        _mint(address(this), initialSupply);
        saleSupply = _saleSupply;
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;
        uniswapPair = _uniswapPair;
        vault = _vault;
    }

    function buyTokens(uint256 amount) external saleActiveOrOwner {
        require(block.timestamp >= saleStartTime && block.timestamp <= saleEndTime, "Sale is not active");
        require(amount > 0, "Amount must be greater than 0");
        require(saleSupply >= amount, "Not enough tokens available for sale");

        _transfer(address(this), msg.sender, amount);
        saleSupply = saleSupply.sub(amount);

        emit TokensPurchased(msg.sender, amount);
    }

    function endSale() external onlyOwner {
        require(block.timestamp > saleEndTime, "Sale has not ended yet");
        require(saleActive, "Sale has already ended");

        // Lock 80% of the sale in the vault
        uint256 lockedAmount = balanceOf(address(this)).mul(80).div(100);
        _transfer(address(this), vault, lockedAmount);

        // Lock the vault for the specified duration
        IUniswapV2Pair(uniswapPair).sync();

        saleActive = false;
    }

    function adjustVesting(address account, uint256 newVestingStart) external onlyOwner notPaused(account) {
        require(newVestingStart > block.timestamp, "New vesting start must be in the future");

        vestingStart[account] = newVestingStart;

        emit VestingAdjusted(account, newVestingStart);
    }

    function pauseVesting(address account) external onlyOwner notPaused(account) {
        vestingPaused[account] = true;

        emit VestingPaused(account);
    }

    function resumeVesting(address account) external onlyOwner {
        vestingPaused[account] = false;

        emit VestingResumed(account);
    }

    function claimVestedTokens() external {
        require(vestingStart[msg.sender] > 0, "Vesting has not started for this account");
        require(!vestingPaused[msg.sender], "Vesting is paused for this account");

        uint256 timeElapsed = block.timestamp.sub(vestingStart[msg.sender]);
        uint256 monthsElapsed = timeElapsed.div(30 days);

        if (monthsElapsed > 0 && monthsElapsed > vestedAmount[msg.sender]) {
            uint256 vestingPercentage = monthsElapsed.mul(25);

            if (vestingPercentage >= 100) {
                vestedAmount[msg.sender] = balanceOf(msg.sender);
            } else {
                vestedAmount[msg.sender] = vestingPercentage.mul(balanceOf(msg.sender)).div(100);
            }

            _transfer(address(this), msg.sender, vestedAmount[msg.sender]);
        }
    }
}
