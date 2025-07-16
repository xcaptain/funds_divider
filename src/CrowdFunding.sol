// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title CrowdFunding
/// @notice Contract for blockchain-based donation platform for universities and research institutions
/// @dev Supports project creation, donations, automatic refunds, and platform fee collection
/// @author Intuipay Team
contract CrowdFunding is Ownable {
    /// @notice Project status enumeration
    enum ProjectStatus {
        Active,     // Active fundraising
        Successful, // Fundraising successful
        Failed      // Fundraising failed
    }
    
    /// @notice Project structure
    struct Project {
        uint256 id;
        string title;
        string description;
        address payable beneficiary;  // University/institution receiving address
        uint256 fundingGoal;         // Target amount
        uint256 deadline;            // Deadline timestamp
        uint256 currentAmount;       // Current raised amount
        ProjectStatus status;
        address tokenAddress;        // Token address (address(0) for native token)
        mapping(address => uint256) contributions; // Contribution records
        address[] contributors;      // Contributors list
    }
    
    /// @notice State variables
    mapping(uint256 => Project) public projects;
    uint256 public projectCount;
    
    /// @notice Platform fee configuration
    address public platformAddress;
    uint256 public platformFeePercentage = 250; // Default 2.5% (250/10000)
    uint256 public constant PERCENTAGE_BASE = 10000;
    
    /// @notice Events
    event ProjectCreated(
        uint256 indexed projectId,
        string title,
        address indexed beneficiary,
        uint256 fundingGoal,
        uint256 deadline,
        address indexed tokenAddress
    );
    
    event ContributionMade(
        uint256 indexed projectId,
        address indexed contributor,
        uint256 amount
    );
    
    event ProjectSuccessful(
        uint256 indexed projectId,
        uint256 totalAmount
    );
    
    event ProjectFailed(
        uint256 indexed projectId
    );
    
    event RefundIssued(
        uint256 indexed projectId,
        address indexed contributor,
        uint256 amount
    );
    
    event FundsWithdrawn(
        uint256 indexed projectId,
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
    error ProjectNotFound();
    error ProjectNotActive();
    error ProjectDeadlinePassed();
    error ProjectNotSuccessful();
    error ProjectNotFailed();
    error OnlyBeneficiaryCanWithdraw();
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
    
    modifier projectExists(uint256 _projectId) {
        if (_projectId == 0 || _projectId > projectCount) revert ProjectNotFound();
        _;
    }
    
    modifier projectActive(uint256 _projectId) {
        if (projects[_projectId].status != ProjectStatus.Active) revert ProjectNotActive();
        if (block.timestamp >= projects[_projectId].deadline) revert ProjectDeadlinePassed();
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
    
    /// @notice Creates a new project
    /// @param _title Project title
    /// @param _description Project description
    /// @param _fundingGoal Target funding amount
    /// @param _durationInDays Duration in days
    /// @param _tokenAddress Token address (address(0) for native token)
    /// @return projectId The created project ID
    function createProject(
        string memory _title,
        string memory _description,
        uint256 _fundingGoal,
        uint256 _durationInDays,
        address _tokenAddress
    ) external onlyValidAmount(_fundingGoal) returns (uint256) {
        if (_durationInDays == 0) revert InvalidDuration();
        
        projectCount++;
        uint256 deadline = block.timestamp + (_durationInDays * 1 days);
        
        Project storage newProject = projects[projectCount];
        newProject.id = projectCount;
        newProject.title = _title;
        newProject.description = _description;
        newProject.beneficiary = payable(msg.sender);
        newProject.fundingGoal = _fundingGoal;
        newProject.deadline = deadline;
        newProject.currentAmount = 0;
        newProject.status = ProjectStatus.Active;
        newProject.tokenAddress = _tokenAddress;
        
        emit ProjectCreated(
            projectCount,
            _title,
            msg.sender,
            _fundingGoal,
            deadline,
            _tokenAddress
        );
        
        return projectCount;
    }
    
    /// @notice Contributes to a project (native token)
    /// @param _projectId The project ID to contribute to
    function contribute(uint256 _projectId) 
        external 
        payable 
        projectExists(_projectId) 
        projectActive(_projectId) 
        onlyValidAmount(msg.value)
    {
        Project storage project = projects[_projectId];
        
        // Check if project accepts native token
        if (project.tokenAddress != address(0)) revert InvalidTokenAddress();
        
        // If it's a new contributor, add to the list
        if (project.contributions[msg.sender] == 0) {
            project.contributors.push(msg.sender);
        }
        
        project.contributions[msg.sender] += msg.value;
        project.currentAmount += msg.value;
        
        emit ContributionMade(_projectId, msg.sender, msg.value);
        
        // Check if funding goal is reached
        if (project.currentAmount >= project.fundingGoal) {
            project.status = ProjectStatus.Successful;
            emit ProjectSuccessful(_projectId, project.currentAmount);
        }
    }
    
    /// @notice Contributes to a project (ERC20 token)
    /// @param _projectId The project ID to contribute to
    /// @param _amount The amount to contribute
    function contributeERC20(uint256 _projectId, uint256 _amount) 
        external 
        projectExists(_projectId) 
        projectActive(_projectId) 
        onlyValidAmount(_amount)
    {
        Project storage project = projects[_projectId];
        
        // Check if project accepts ERC20 token
        if (project.tokenAddress == address(0)) revert InvalidTokenAddress();
        
        IERC20 token = IERC20(project.tokenAddress);
        
        // Check user's token balance
        if (token.balanceOf(msg.sender) < _amount) revert InsufficientBalance();
        
        // Check allowance
        if (token.allowance(msg.sender, address(this)) < _amount) revert InsufficientAllowance();
        
        // Transfer tokens from user to contract
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        if (!success) revert TransferFailed();
        
        // If it's a new contributor, add to the list
        if (project.contributions[msg.sender] == 0) {
            project.contributors.push(msg.sender);
        }
        
        project.contributions[msg.sender] += _amount;
        project.currentAmount += _amount;
        
        emit ContributionMade(_projectId, msg.sender, _amount);
        
        // Check if funding goal is reached
        if (project.currentAmount >= project.fundingGoal) {
            project.status = ProjectStatus.Successful;
            emit ProjectSuccessful(_projectId, project.currentAmount);
        }
    }
    
    /// @notice Checks and updates project status
    /// @param _projectId The project ID to check
    function checkProjectStatus(uint256 _projectId) 
        external 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        
        if (project.status == ProjectStatus.Active && 
            block.timestamp >= project.deadline) {
            
            if (project.currentAmount >= project.fundingGoal) {
                project.status = ProjectStatus.Successful;
                emit ProjectSuccessful(_projectId, project.currentAmount);
            } else {
                project.status = ProjectStatus.Failed;
                emit ProjectFailed(_projectId);
            }
        }
    }
    
    /// @notice Withdraws funds (called by beneficiary after project success)
    /// @param _projectId The project ID to withdraw from
    function withdrawFunds(uint256 _projectId) 
        external 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        if (project.status != ProjectStatus.Successful) revert ProjectNotSuccessful();
        if (msg.sender != project.beneficiary) revert OnlyBeneficiaryCanWithdraw();
        if (project.currentAmount == 0) revert NoFundsToWithdraw();
        
        uint256 totalAmount = project.currentAmount;
        uint256 platformFee = (totalAmount * platformFeePercentage) / PERCENTAGE_BASE;
        uint256 beneficiaryAmount = totalAmount - platformFee;
        
        // Reset amount to prevent reentrancy
        project.currentAmount = 0;
        
        if (project.tokenAddress == address(0)) {
            // Native token transfer
            (bool beneficiarySuccess, ) = project.beneficiary.call{value: beneficiaryAmount}("");
            if (!beneficiarySuccess) revert TransferFailed();
            
            (bool platformSuccess, ) = platformAddress.call{value: platformFee}("");
            if (!platformSuccess) revert TransferFailed();
        } else {
            // ERC20 token transfer
            IERC20 token = IERC20(project.tokenAddress);
            
            // Transfer to beneficiary
            bool beneficiarySuccess = token.transfer(project.beneficiary, beneficiaryAmount);
            if (!beneficiarySuccess) revert TransferFailed();
            
            // Transfer platform fee
            bool platformSuccess = token.transfer(platformAddress, platformFee);
            if (!platformSuccess) revert TransferFailed();
        }
        
        emit FundsWithdrawn(_projectId, project.beneficiary, beneficiaryAmount, platformFee);
    }
    
    /// @notice Requests refund (called by contributors after project failure)
    /// @param _projectId The project ID to request refund from
    function requestRefund(uint256 _projectId) 
        external 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        if (project.status != ProjectStatus.Failed) revert ProjectNotFailed();
        if (project.contributions[msg.sender] == 0) revert NoContributionFound();
        
        uint256 refundAmount = project.contributions[msg.sender];
        project.contributions[msg.sender] = 0;
        
        if (project.tokenAddress == address(0)) {
            // Native token refund
            (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token refund
            IERC20 token = IERC20(project.tokenAddress);
            bool success = token.transfer(msg.sender, refundAmount);
            if (!success) revert TransferFailed();
        }
        
        emit RefundIssued(_projectId, msg.sender, refundAmount);
    }
    
    /// @notice Gets project details
    /// @param _projectId The project ID
    /// @return id Project ID
    /// @return title Project title
    /// @return description Project description
    /// @return beneficiary Beneficiary address
    /// @return fundingGoal Funding goal amount
    /// @return deadline Project deadline timestamp
    /// @return currentAmount Current raised amount
    /// @return status Project status
    /// @return contributorsCount Number of contributors
    function getProjectDetails(uint256 _projectId) 
        external 
        view 
        projectExists(_projectId) 
        returns (
            uint256 id,
            string memory title,
            string memory description,
            address beneficiary,
            uint256 fundingGoal,
            uint256 deadline,
            uint256 currentAmount,
            ProjectStatus status,
            uint256 contributorsCount
        ) 
    {
        Project storage project = projects[_projectId];
        return (
            project.id,
            project.title,
            project.description,
            project.beneficiary,
            project.fundingGoal,
            project.deadline,
            project.currentAmount,
            project.status,
            project.contributors.length
        );
    }
    
    /// @notice Gets user's contribution to a specific project
    /// @param _projectId The project ID
    /// @param _contributor The contributor address
    /// @return The contribution amount
    function getUserContribution(uint256 _projectId, address _contributor) 
        external 
        view 
        projectExists(_projectId) 
        returns (uint256) 
    {
        return projects[_projectId].contributions[_contributor];
    }
    
    /// @notice Gets all contributors of a project
    /// @param _projectId The project ID
    /// @return Array of contributor addresses
    function getProjectContributors(uint256 _projectId) 
        external 
        view 
        projectExists(_projectId) 
        returns (address[] memory) 
    {
        return projects[_projectId].contributors;
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
