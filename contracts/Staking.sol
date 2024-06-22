// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "./Token.sol";
// import "hardhat/console.sol";

// This smart contract contains a staking mechanism for the wBNRY token. 
// Accumulated wBNRY in this smart contract will be used to spin up evo nodes on the BNRY network. 
// For more information on the project, you can visit https://binarybit.pro/

interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract Staking is ReentrancyGuard, Pausable, Ownable {
    IToken public token;
    uint256 public totalTokensStaked;
    uint256 public totalStakers;
    uint256 public totalTreasuryTokens;
    uint256 public annualYield;

    uint256 public constant SECONDS_IN_YEAR = 365 * 24 * 60 * 60; //31 536 000 seconds
    uint256 public constant PRECISION = 1e18;

    struct Participant {
        address user;
        uint256 latestActionTime;
        uint256 directStakeAmountSatoshi;
        uint256 rewardAmountSatoshi;
    }

    event Stake(address indexed customer, uint256 amount_wbnry);
    event Withdraw(address indexed customer, uint256 amount_wbnry);
    event FundTreasury(address indexed funder, uint256 amount_wbnry);
    event AnnualYieldChanged(uint256 newAnnualYield);

    address[] public customerAddressesArray;
    mapping(address => Participant) public customerMapping;

    constructor(IToken _token) {
        token = _token;
        totalTokensStaked = 0;
        totalStakers = 0;
        totalTreasuryTokens = 0;
        annualYield = 60; // 60% annual yield
    }

    modifier amountGreaterThanZero(uint256 _tokenAmountSatoshi) {
        require(_tokenAmountSatoshi > 0, "Token amount must be greater than zero");
        _;
    }

    // This function is just for testing purposes
    // function calculateCurrentBalanceLinear(address user) public view returns (uint256) {
    //     Participant storage participant = customerMapping[user];
    //     uint256 startTime = participant.latestActionTime;
    //     uint256 initialAmount = participant.directStakeAmountSatoshi + participant.rewardAmountSatoshi;

    //     uint256 timeElapsed = block.timestamp - startTime;
    //     uint256 ratePerSecond = (annualYield * PRECISION) / (100 * SECONDS_IN_YEAR);

    //     // Calculate linear interest with precision
    //     uint256 accruedInterest = initialAmount * ratePerSecond * timeElapsed / PRECISION;
    //     uint256 currentBalance = initialAmount + accruedInterest;
    //     return currentBalance;
    // }

    function calculateCurrentBalanceCompound(address user) public view returns (uint256) {
        Participant storage participant = customerMapping[user];
        uint256 startTime = participant.latestActionTime;
        uint256 initialAmount = participant.directStakeAmountSatoshi + participant.rewardAmountSatoshi;

        uint256 timeElapsed = block.timestamp - startTime;
        uint256 ratePerSecond = (annualYield * PRECISION) / SECONDS_IN_YEAR / 100;

        // Compound interest approximation
        uint256 base = PRECISION + ratePerSecond;
        uint256 compoundedAmount = initialAmount;

        while (timeElapsed > 0) {
            if (timeElapsed % 2 == 1) {
                compoundedAmount = compoundedAmount * base / PRECISION;
            }
            base = base * base / PRECISION;
            timeElapsed /= 2;
        }

        return compoundedAmount;
    }

        function stake(uint256 _tokenAmountSatoshi) public amountGreaterThanZero(_tokenAmountSatoshi) whenNotPaused nonReentrant {
        Participant storage participant = customerMapping[msg.sender];
        participant.rewardAmountSatoshi += calculateCurrentBalanceCompound(msg.sender) - participant.directStakeAmountSatoshi - participant.rewardAmountSatoshi;

        require(token.balanceOf(msg.sender) >= _tokenAmountSatoshi, "insufficient token balance");
        require(token.allowance(msg.sender, address(this)) >= _tokenAmountSatoshi, "insufficient allowance");

        // Transfer tokens from the sender to the contract
        bool success = token.transferFrom(msg.sender, address(this), _tokenAmountSatoshi);
        require(success, "Token transfer failed");

        if (customerMapping[msg.sender].user == address(0)) {
            customerAddressesArray.push(msg.sender);
            totalStakers += 1;
        }

        participant.user = msg.sender;
        participant.latestActionTime = block.timestamp;
        participant.directStakeAmountSatoshi += _tokenAmountSatoshi;

        totalTokensStaked += _tokenAmountSatoshi;

        emit Stake(msg.sender, _tokenAmountSatoshi);
    }

    function withdraw(uint256 _tokenAmountSatoshi) public amountGreaterThanZero(_tokenAmountSatoshi) whenNotPaused nonReentrant {
        Participant storage participant = customerMapping[msg.sender];
        uint256 currentBalance = calculateCurrentBalanceCompound(msg.sender);
        uint256 rewardAmount = currentBalance - participant.directStakeAmountSatoshi - participant.rewardAmountSatoshi;
        participant.rewardAmountSatoshi += rewardAmount;

        uint256 totalBalance = participant.directStakeAmountSatoshi + participant.rewardAmountSatoshi;
        require(totalBalance >= _tokenAmountSatoshi, "insufficient total token balance");

        uint256 amountToWithdrawFromTreasury;
        uint256 directStakeReduction;

        if (_tokenAmountSatoshi > participant.rewardAmountSatoshi) {
            amountToWithdrawFromTreasury = participant.rewardAmountSatoshi;
            directStakeReduction = _tokenAmountSatoshi - amountToWithdrawFromTreasury;
            require(totalTreasuryTokens >= amountToWithdrawFromTreasury, "insufficient treasury token balance");

            totalTokensStaked -= directStakeReduction;
            participant.directStakeAmountSatoshi -= directStakeReduction;
            participant.rewardAmountSatoshi = 0;
        } else {
            amountToWithdrawFromTreasury = _tokenAmountSatoshi;
            require(totalTreasuryTokens >= amountToWithdrawFromTreasury, "insufficient treasury token balance");

            participant.rewardAmountSatoshi -= _tokenAmountSatoshi;
        }

        totalTreasuryTokens -= amountToWithdrawFromTreasury;
        participant.latestActionTime = block.timestamp;

        bool success = token.transfer(msg.sender, _tokenAmountSatoshi);
        require(success, "Token transfer failed");

        emit Withdraw(msg.sender, _tokenAmountSatoshi);
    }

    // This function is just for testing purposes, needs to be disabled in production
    function updateTimestamp(address user, uint256 newTimestamp) public onlyOwner {
        require(customerMapping[user].user != address(0), "User does not exist");
        customerMapping[user].latestActionTime = newTimestamp;
    }

    function getParticipant(address _customer) public view returns (Participant memory) {
        Participant memory participant = customerMapping[_customer];
        return (participant);
    }

    function getCustomerAddressesArray() public view returns (address[] memory) {
        return customerAddressesArray;
    }

    function fundTreasury(uint256 _tokenAmountSatoshi) public amountGreaterThanZero(_tokenAmountSatoshi) whenNotPaused nonReentrant {
        totalTreasuryTokens += _tokenAmountSatoshi;

        token.approve(address(this), _tokenAmountSatoshi);
        token.transferFrom(msg.sender, address(this), _tokenAmountSatoshi);

        emit FundTreasury(msg.sender, _tokenAmountSatoshi);
    }

    function changeAnnualYield(uint256 _newAnnualYield) public onlyOwner whenNotPaused nonReentrant {
        for (uint256 i = 0; i < customerAddressesArray.length; i++) {
            address user = customerAddressesArray[i];
            Participant storage participant = customerMapping[user];
            uint256 currentBalance = calculateCurrentBalanceCompound(user);
            participant.rewardAmountSatoshi += currentBalance - participant.directStakeAmountSatoshi - participant.rewardAmountSatoshi;
            participant.latestActionTime = block.timestamp;
        }
        annualYield = _newAnnualYield;
        emit AnnualYieldChanged(_newAnnualYield);
    }

    // Function to pause the contract
    function pause() public onlyOwner {
        _pause();
    }

    // Function to unpause the contract
    function unpause() public onlyOwner {
        _unpause();
    }
}
