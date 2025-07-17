// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title CrowdFunding
/// @notice Contract for blockchain-based donation platform for universities and research institutions
/// @dev Supports project creation, donations, automatic refunds, and platform fee collection
/// @author Intuipay Team
contract CrowdFunding is Ownable {
    /// @notice Campaign status enumeration
    enum CampaignStatus {
        Active,     // Active fundraising
        Successful, // Fundraising successful
        Failed      // Fundraising failed
    }
    
    /// @notice Campaign structure
    struct Campaign {
        uint256 id;
        string title;
        string description;
        address beneficiary;  // University/institution receiving address
        uint256 fundingGoal;         // Target amount
        uint256 deadline;            // Deadline timestamp
        uint256 currentAmount;       // Current raised amount
        CampaignStatus status;
        address tokenAddress;        // Token address (address(0) for native token)
        mapping(address => uint256) contributions; // Contribution records
        address[] contributors;      // Contributors list
    }
    
    /// @notice State variables
    mapping(uint256 => Campaign) public campaigns;
    uint256 public campaignCount;
    
    /// @notice Platform fee configuration
    address public platformAddress;
    uint256 public platformFeePercentage = 300; // Default 3% (300/10000)
    uint256 public constant PERCENTAGE_BASE = 10000;
    
    /// @notice Events
    event CampaignCreated(
        uint256 indexed campaignId,
        string title,
        address indexed beneficiary,
        uint256 fundingGoal,
        uint256 deadline,
        address indexed tokenAddress
    );
    
    event ContributionMade(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    
    event CampaignSuccessful(
        uint256 indexed campaignId,
        uint256 totalAmount
    );
    
    event CampaignFailed(
        uint256 indexed campaignId
    );
    
    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    
    event FundsWithdrawn(
        uint256 indexed campaignId,
        address indexed beneficiary,
        uint256 netAmount,
        uint256 platformFee
    );
    
    event PlatformAddressUpdated(
        address indexed oldPlatformAddress,
        address indexed newPlatformAddress
    );
    
    event PlatformFeePercentageUpdated(
        uint256 oldFeePercentage,
        uint256 newFeePercentage
    );
    
    /// @notice Errors
    error InvalidAddress();
    error InvalidAmount();
    error TransferFailed();
    error CampaignNotFound();
    error CampaignNotActive();
    error CampaignDeadlinePassed();
    error CampaignNotSuccessful();
    error CampaignNotFailed();
    error NoContributionFound();
    error NoFundsToWithdraw();
    error InvalidFeePercentage();
    error InvalidDuration();
    error InvalidFundingGoal();
    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidTokenAddress();
    
    /// @notice Modifiers
    modifier onlyValidAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }
    
    modifier onlyValidAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }
    
    modifier campaignExists(uint256 _campaignId) {
        if (_campaignId == 0 || _campaignId > campaignCount) revert CampaignNotFound();
        _;
    }
    
    modifier campaignActive(uint256 _campaignId) {
        if (campaigns[_campaignId].status != CampaignStatus.Active) revert CampaignNotActive();
        if (block.timestamp >= campaigns[_campaignId].deadline) revert CampaignDeadlinePassed();
        _;
    }
    
    /// @notice Constructor
    /// @param initialOwner The administrator address
    /// @param _platformAddress The platform address to receive fees
    constructor(
        address initialOwner,
        address _platformAddress
    ) Ownable(initialOwner) onlyValidAddress(_platformAddress) {
        platformAddress = _platformAddress;
    }
    
    /// @notice Updates the platform address
    /// @param _newPlatformAddress The new platform address
    function updatePlatformAddress(
        address _newPlatformAddress
    ) external onlyOwner onlyValidAddress(_newPlatformAddress) {
        address oldPlatformAddress = platformAddress;
        platformAddress = _newPlatformAddress;
        emit PlatformAddressUpdated(oldPlatformAddress, _newPlatformAddress);
    }
    
    /// @notice Updates the platform fee percentage
    /// @param _newFeePercentage The new fee percentage (based on 10000, cannot exceed 100%)
    function updatePlatformFeePercentage(uint256 _newFeePercentage) external onlyOwner {
        if (_newFeePercentage > PERCENTAGE_BASE) revert InvalidFeePercentage();
        uint256 oldFeePercentage = platformFeePercentage;
        platformFeePercentage = _newFeePercentage;
        emit PlatformFeePercentageUpdated(oldFeePercentage, _newFeePercentage);
    }
    
    /// @notice Creates a new campaign (only admin can create)
    /// @param _title Campaign title
    /// @param _description Campaign description
    /// @param _beneficiary Campaign beneficiary (university/institution address)
    /// @param _fundingGoal Target funding amount
    /// @param _durationInDays Duration in days
    /// @param _tokenAddress Token address (address(0) for native token)
    /// @return campaignId The created campaign ID
    function createCampaign(
        string memory _title,
        string memory _description,
        address _beneficiary,
        uint256 _fundingGoal,
        uint256 _durationInDays,
        address _tokenAddress
    ) external onlyOwner onlyValidAddress(_beneficiary) onlyValidAmount(_fundingGoal) returns (uint256) {
        if (_durationInDays == 0) revert InvalidDuration();
        
        campaignCount++;
        uint256 deadline = block.timestamp + (_durationInDays * 1 days);
        
        Campaign storage newCampaign = campaigns[campaignCount];
        newCampaign.id = campaignCount;
        newCampaign.title = _title;
        newCampaign.description = _description;
        newCampaign.beneficiary = _beneficiary;
        newCampaign.fundingGoal = _fundingGoal;
        newCampaign.deadline = deadline;
        newCampaign.currentAmount = 0;
        newCampaign.status = CampaignStatus.Active;
        newCampaign.tokenAddress = _tokenAddress;
        
        emit CampaignCreated(
            campaignCount,
            _title,
            _beneficiary,
            _fundingGoal,
            deadline,
            _tokenAddress
        );
        
        return campaignCount;
    }
    
    /// @notice Contributes to a campaign (native token)
    /// @param _campaignId The campaign ID to contribute to
    function contribute(uint256 _campaignId) 
        external 
        payable 
        campaignExists(_campaignId) 
        campaignActive(_campaignId) 
        onlyValidAmount(msg.value)
    {
        Campaign storage campaign = campaigns[_campaignId];
        
        // Check if campaign accepts native token
        if (campaign.tokenAddress != address(0)) revert InvalidTokenAddress();
        
        // If it's a new contributor, add to the list
        if (campaign.contributions[msg.sender] == 0) {
            campaign.contributors.push(msg.sender);
        }
        
        campaign.contributions[msg.sender] += msg.value;
        campaign.currentAmount += msg.value;
        
        emit ContributionMade(_campaignId, msg.sender, msg.value);
        
        // Check if funding goal is reached
        if (campaign.currentAmount >= campaign.fundingGoal) {
            campaign.status = CampaignStatus.Successful;
            emit CampaignSuccessful(_campaignId, campaign.currentAmount);
        }
    }
    
    /// @notice Contributes to a campaign (ERC20 token)
    /// @param _campaignId The campaign ID to contribute to
    /// @param _amount The amount to contribute
    function contributeERC20(uint256 _campaignId, uint256 _amount) 
        external 
        campaignExists(_campaignId) 
        campaignActive(_campaignId) 
        onlyValidAmount(_amount)
    {
        Campaign storage campaign = campaigns[_campaignId];
        
        // Check if campaign accepts ERC20 token
        if (campaign.tokenAddress == address(0)) revert InvalidTokenAddress();
        
        IERC20 token = IERC20(campaign.tokenAddress);
        
        // Check user's token balance
        if (token.balanceOf(msg.sender) < _amount) revert InsufficientBalance();
        
        // Check allowance
        if (token.allowance(msg.sender, address(this)) < _amount) revert InsufficientAllowance();
        
        // Transfer tokens from user to contract
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        if (!success) revert TransferFailed();
        
        // If it's a new contributor, add to the list
        if (campaign.contributions[msg.sender] == 0) {
            campaign.contributors.push(msg.sender);
        }
        
        campaign.contributions[msg.sender] += _amount;
        campaign.currentAmount += _amount;
        
        emit ContributionMade(_campaignId, msg.sender, _amount);
        
        // Check if funding goal is reached
        if (campaign.currentAmount >= campaign.fundingGoal) {
            campaign.status = CampaignStatus.Successful;
            emit CampaignSuccessful(_campaignId, campaign.currentAmount);
        }
    }
    
    /// @notice Checks and updates campaign status
    /// @param _campaignId The campaign ID to check
    function checkCampaignStatus(uint256 _campaignId) 
        external 
        campaignExists(_campaignId) 
    {
        Campaign storage campaign = campaigns[_campaignId];
        
        if (campaign.status == CampaignStatus.Active && 
            block.timestamp >= campaign.deadline) {
            
            if (campaign.currentAmount >= campaign.fundingGoal) {
                campaign.status = CampaignStatus.Successful;
                emit CampaignSuccessful(_campaignId, campaign.currentAmount);
            } else {
                campaign.status = CampaignStatus.Failed;
                emit CampaignFailed(_campaignId);
            }
        }
    }
    
    /// @notice Withdraws funds (can be called by anyone after campaign success)
    /// @param _campaignId The campaign ID to withdraw from
    function withdrawFunds(uint256 _campaignId) 
        external 
        campaignExists(_campaignId) 
    {
        Campaign storage campaign = campaigns[_campaignId];
        if (campaign.status != CampaignStatus.Successful) revert CampaignNotSuccessful();
        if (campaign.currentAmount == 0) revert NoFundsToWithdraw();
        
        uint256 totalAmount = campaign.currentAmount;
        uint256 platformFee = (totalAmount * platformFeePercentage) / PERCENTAGE_BASE;
        uint256 beneficiaryAmount = totalAmount - platformFee;
        
        // Reset amount to prevent reentrancy
        campaign.currentAmount = 0;
        
        if (campaign.tokenAddress == address(0)) {
            // Native token transfer
            (bool beneficiarySuccess, ) = payable(campaign.beneficiary).call{value: beneficiaryAmount}("");
            if (!beneficiarySuccess) revert TransferFailed();
            
            (bool platformSuccess, ) = payable(platformAddress).call{value: platformFee}("");
            if (!platformSuccess) revert TransferFailed();
        } else {
            // ERC20 token transfer
            IERC20 token = IERC20(campaign.tokenAddress);
            
            // Transfer to beneficiary
            bool beneficiarySuccess = token.transfer(campaign.beneficiary, beneficiaryAmount);
            if (!beneficiarySuccess) revert TransferFailed();
            
            // Transfer platform fee
            bool platformSuccess = token.transfer(platformAddress, platformFee);
            if (!platformSuccess) revert TransferFailed();
        }
        
        emit FundsWithdrawn(_campaignId, campaign.beneficiary, beneficiaryAmount, platformFee);
    }
    
    /// @notice Requests refund (called by contributors after campaign failure)
    /// @param _campaignId The campaign ID to request refund from
    function requestRefund(uint256 _campaignId) 
        external 
        campaignExists(_campaignId) 
    {
        Campaign storage campaign = campaigns[_campaignId];
        if (campaign.status != CampaignStatus.Failed) revert CampaignNotFailed();
        if (campaign.contributions[msg.sender] == 0) revert NoContributionFound();
        
        uint256 refundAmount = campaign.contributions[msg.sender];
        campaign.contributions[msg.sender] = 0;
        
        if (campaign.tokenAddress == address(0)) {
            // Native token refund
            (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token refund
            IERC20 token = IERC20(campaign.tokenAddress);
            bool success = token.transfer(msg.sender, refundAmount);
            if (!success) revert TransferFailed();
        }
        
        emit RefundIssued(_campaignId, msg.sender, refundAmount);
    }
    
    /// @notice Gets campaign details
    /// @param _campaignId The campaign ID
    /// @return id Campaign ID
    /// @return title Campaign title
    /// @return description Campaign description
    /// @return beneficiary Beneficiary address
    /// @return fundingGoal Funding goal amount
    /// @return deadline Campaign deadline timestamp
    /// @return currentAmount Current raised amount
    /// @return status Campaign status
    /// @return contributorsCount Number of contributors
    function getCampaignDetails(uint256 _campaignId) 
        external 
        view 
        campaignExists(_campaignId) 
        returns (
            uint256 id,
            string memory title,
            string memory description,
            address beneficiary,
            uint256 fundingGoal,
            uint256 deadline,
            uint256 currentAmount,
            CampaignStatus status,
            uint256 contributorsCount
        ) 
    {
        Campaign storage campaign = campaigns[_campaignId];
        return (
            campaign.id,
            campaign.title,
            campaign.description,
            campaign.beneficiary,
            campaign.fundingGoal,
            campaign.deadline,
            campaign.currentAmount,
            campaign.status,
            campaign.contributors.length
        );
    }
    
    /// @notice Gets user's contribution to a specific campaign
    /// @param _campaignId The campaign ID
    /// @param _contributor The contributor address
    /// @return The contribution amount
    function getUserContribution(uint256 _campaignId, address _contributor) 
        external 
        view 
        campaignExists(_campaignId) 
        returns (uint256) 
    {
        return campaigns[_campaignId].contributions[_contributor];
    }
    
    /// @notice Gets all contributors of a campaign
    /// @param _campaignId The campaign ID
    /// @return Array of contributor addresses
    function getCampaignContributors(uint256 _campaignId) 
        external 
        view 
        campaignExists(_campaignId) 
        returns (address[] memory) 
    {
        return campaigns[_campaignId].contributors;
    }
    
    /// @notice Calculates platform fee and net amount
    /// @param totalAmount The total amount
    /// @return platformFee The platform fee amount
    /// @return netAmount The net amount after fee deduction
    function calculateAmounts(
        uint256 totalAmount
    ) external view returns (uint256 platformFee, uint256 netAmount) {
        platformFee = (totalAmount * platformFeePercentage) / PERCENTAGE_BASE;
        netAmount = totalAmount - platformFee;
    }
    
    /// @notice Gets contract balance
    /// @return The contract balance
    function getContractBalance() 
        external 
        view 
        returns (uint256) 
    {
        return address(this).balance;
    }
    
    /// @notice Emergency withdrawal (only owner, for emergency situations)
    function emergencyWithdraw() 
        external 
        onlyOwner 
    {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }
}
