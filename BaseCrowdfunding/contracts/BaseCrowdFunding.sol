// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface ERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract BaseCrowdFunding {
    struct Campaign {
        address owner;
        string title;
        string description;
        uint256 target;
        uint256 deadline;
        uint256 amountCollected;
        uint256 amountCollectedERC20;
        string image;
        address[] donators;
        uint256[] donations;
        uint256[] donationsERC20;
        bool canceled;
    }

    mapping(uint256 => Campaign) public campaigns;
    uint256 public numberOfCampaigns = 0;
    uint256 public campaignCreationFee = 0.000314 ether;
    address public feeWallet;
    address public contractOwner;
    IERC20 public erc20Token;
    address public erc1155Address;
    address public erc721Address;
    uint256 public freeCampaignCreationLimit1 = 1;
    uint256 public freeCampaignCreationLimit2 = 3;
    mapping(address => uint256) public freeCampaignCreations;
    bool public enableFreeCampaignCreationLimits = true;
    event CampaignCreated(address indexed creator, uint256 campaignId);
    event DonationReceived(uint256 indexed campaignId, address indexed donor, uint256 amount, bool isEther);
    event CampaignCanceled(uint256 indexed campaignId);
    event FundsWithdrawn(uint256 indexed campaignId);

    modifier onlyOwner() {
        require(msg.sender == contractOwner, "Only the contract owner can call this function.");
        _;
    }

    constructor() {
        contractOwner = msg.sender;
        feeWallet = address(0x864AE6a6d4F7cF4B25140dc28E0F8f29Bfe4Cb48);
        erc20Token = IERC20(0xC1B6844D5134c8E550043f01FFbF49CA66Efc77F);
        erc1155Address = address(0x9D4fa04B3eF4e623b3807E44Cf8072C08123e1f9);
        erc721Address = address(0x617e2b0cE5AE1C5b93Acbd4181F10A6fbc225905);
    }

    function addNFTCollectionAddresses(address erc1155, address erc721) public onlyOwner {
        erc1155Address = erc1155;
        erc721Address = erc721;
    }

    function changeERC20Token(address newERC20Token) public onlyOwner {
        erc20Token = IERC20(newERC20Token);
    }
    
    function toggleFreeCampaignCreationLimits(bool enable) public onlyOwner {
        enableFreeCampaignCreationLimits = enable;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        contractOwner = newOwner;
    }

    function changeCampaignCreationFee(uint256 newFee) public onlyOwner {
        campaignCreationFee = newFee;
    }

    function createCampaign(
        string memory _title,
        string memory _description,
        uint256 _target,
        uint256 _deadline,
        string memory _image
    ) public payable {
        require(_deadline > block.timestamp, "The deadline should be a date in the future");

        // Declare variables to check NFT ownership
        bool ownsNFTCollection1 = ERC1155(erc1155Address).balanceOf(msg.sender, 0) > 0;
        bool ownsNFTCollection2 = ERC721(erc721Address).ownerOf(0) == msg.sender;

        // Check if the caller is the contract owner and allow free creation
        if (msg.sender != contractOwner) {
            // Check if the caller is eligible for free campaign creation
            if (enableFreeCampaignCreationLimits) {
                if (ownsNFTCollection1 && freeCampaignCreations[msg.sender] < freeCampaignCreationLimit1) {
                    // Allow free creation for users with NFTs from collection 1
                    freeCampaignCreations[msg.sender]++;
                } else if (ownsNFTCollection2 && freeCampaignCreations[msg.sender] < freeCampaignCreationLimit2) {
                    // Allow free creation for users with NFTs from collection 2 within the limit
                    freeCampaignCreations[msg.sender]++;
                } else {
                    require(msg.value >= campaignCreationFee, "Insufficient fee");
                }
            } else {
                require(msg.value >= campaignCreationFee, "Insufficient fee");
            }
        }

        Campaign storage campaign = campaigns[numberOfCampaigns];

        campaign.owner = msg.sender;
        campaign.title = _title;
        campaign.description = _description;
        campaign.target = _target;
        campaign.deadline = _deadline;
        campaign.amountCollected = 0;
        campaign.amountCollectedERC20 = 0;
        campaign.image = _image;

        // Refund any excess fee if the caller is not the contract owner and is not eligible for free creation
        if (msg.sender != contractOwner && !enableFreeCampaignCreationLimits && !ownsNFTCollection1 && !ownsNFTCollection2 && msg.value > campaignCreationFee) {
            payable(msg.sender).transfer(msg.value - campaignCreationFee);
        }

        numberOfCampaigns++;

        emit CampaignCreated(msg.sender, numberOfCampaigns - 1);
    }

    function cancelCampaign(uint256 _id) public {
        require(_id < numberOfCampaigns, "Campaign does not exist");
        Campaign storage campaign = campaigns[_id];
        require(msg.sender == campaign.owner, "Only the owner can cancel the campaign");
        require(!campaign.canceled, "Campaign is already canceled");

        if (campaign.amountCollected < campaign.target) {
            campaign.canceled = true;
            // Refund donations to donors
            for (uint256 i = 0; i < campaign.donators.length; i++) {
                address donor = campaign.donators[i];
                uint256 amount = campaign.donations[i];
                if (amount > 0) {
                    (bool sent, ) = payable(donor).call{value: amount}("");
                    require(sent, "Refund failed");
                }
            }

            emit CampaignCanceled(_id);
        }
    }

    function withdrawFunds(uint256 _id) public {
        require(_id < numberOfCampaigns, "Campaign does not exist");
        Campaign storage campaign = campaigns[_id];
        require(msg.sender == campaign.owner, "Only the owner can withdraw funds");
        require(!campaign.canceled, "Canceled campaigns cannot withdraw funds");
        require(campaign.amountCollected >= campaign.target, "Target not met");

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool sent, ) = payable(msg.sender).call{value: balance}("");
            require(sent, "Withdrawal failed");
            emit FundsWithdrawn(_id);
        }
    }

    function donateToCampaign(uint256 _id) public payable {
        uint256 amount = msg.value;
        Campaign storage campaign = campaigns[_id];
        require(campaign.deadline > block.timestamp, "The campaign has ended");
        require(amount > 0, "Donation amount must be greater than zero");

        campaign.donators.push(msg.sender);
        campaign.donations.push(amount);

        // Send the donation to the campaign owner
        (bool sent, ) = payable(campaign.owner).call{value: amount}("");
        require(sent, "Donation failed");
        campaign.amountCollected += amount;

        emit DonationReceived(_id, msg.sender, amount, true);
    }

    function donateERC20ToCampaign(uint256 _id, uint256 _amount) public {
        require(_amount > 0, "Donation amount must be greater than 0");
        Campaign storage campaign = campaigns[_id];
        uint256 allowance = erc20Token.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Allowance not sufficient");
        bool success = erc20Token.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");
        campaign.donators.push(msg.sender);
        campaign.donationsERC20.push(_amount);
        campaign.amountCollectedERC20 += _amount;

        emit DonationReceived(_id, msg.sender, _amount, false);
    }

    function getDonators(uint256 _id) public view returns (address[] memory, uint256[] memory) {
        Campaign storage campaign = campaigns[_id];
        return (campaign.donators, campaign.donations);
    }

    function getNumberOfCampaigns() public view returns (uint256) {
        return numberOfCampaigns;
    }

    function getCampaign(uint256 _id) public view returns (Campaign memory) {
        require(_id < numberOfCampaigns, "Campaign does not exist");
        return campaigns[_id];
    }

    function getAllCampaigns() public view returns (Campaign[] memory) {
        Campaign[] memory allCampaigns = new Campaign[](numberOfCampaigns);

        for (uint256 i = 0; i < numberOfCampaigns; i++) {
            allCampaigns[i] = campaigns[i];
        }

        return allCampaigns;
    }
}