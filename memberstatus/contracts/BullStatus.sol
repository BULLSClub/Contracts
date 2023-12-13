// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Import ERC-721 and ERC-721 Enumerable interfaces
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract BullStatus {
    uint256 constant MAX_CHARACTER_AMOUNT = 134;

    struct StatusInfo {
        string name;
        string family;
        string status;
        uint256 timestamp;
    }

    mapping(address => StatusInfo) private userStatuses;
    mapping(uint256 => StatusInfo) private allStatuses;
    address private nftCollectionAddress = 0x617e2b0cE5AE1C5b93Acbd4181F10A6fbc225905;

    event StatusUpdated(string name, string family, string newStatus, uint256 timestamp);

    modifier onlyNFTOwner(uint256 _tokenId) {
        require(isNFTOwner(msg.sender, _tokenId), "Caller does not own the specified NFT");
        _;
    }

    function isNFTOwner(address _user, uint256 _tokenId) internal view returns (bool) {
        IERC721 nftContract = IERC721(nftCollectionAddress);
        return nftContract.ownerOf(_tokenId) == _user;
    }

    function getAnyRandomNFTId(address _user) internal view returns (uint256) {
        IERC721Enumerable nftContract = IERC721Enumerable(nftCollectionAddress);
        uint256 balance = nftContract.balanceOf(_user);

        require(balance > 0, "User does not own any NFT");

        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, _user))) % balance;

        // Use tokenOfOwnerByIndex to get the NFT at the random index
        uint256 tokenId = nftContract.tokenOfOwnerByIndex(_user, randomIndex);

        return tokenId;
    }

    function getTokenURI(uint256 _tokenId) internal view returns (string memory) {
        // Assuming that the NFT contract has a function to get the token URI by NFT ID
        // Replace this with the actual function from your NFT contract
        // For example: nftContract.tokenURI(_nftId);
        return "ipfs://Qmb6RP9r7WraRinSAXMJLC5xwag5WeWqWZBmPB2rhLbQsd/"; // Replace with actual logic
    }

    function decodeIPFSMetadata(string memory _tokenURI) internal view returns (string memory, string memory) {
        string memory prefix = "ipfs://Qmb6RP9r7WraRinSAXMJLC5xwag5WeWqWZBmPB2rhLbQsd/";

        require(bytes(_tokenURI).length > bytes(prefix).length, "Invalid token URI");
        string memory ipfsPath = substring(_tokenURI, bytes(prefix).length, bytes(_tokenURI).length - bytes(prefix).length);

        // Directly use the known IPFS path to get the metadata
        string memory metadata = fetchMetadataFromIPFS(ipfsPath);

        return (parseField(metadata, "name"), parseField(metadata, "family"));
    }

    function fetchMetadataFromIPFS(string memory _ipfsPath) internal view returns (string memory) {
        // In this example, we'll return a fixed metadata string
        // You should replace this with your actual logic to fetch metadata based on the IPFS path
        return "{'name':'John', 'family':'Doe'}";
    }

    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        require(startIndex < endIndex && endIndex <= strBytes.length, "Invalid substring indices");
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function parseField(string memory metadata, string memory field) internal pure returns (string memory) {
        string memory searchKey = string(abi.encodePacked('"', field, '":'));
        uint256 startIndex = bytes(metadata).length;
        uint256 endIndex = bytes(metadata).length;

        for (uint256 i = 0; i < bytes(metadata).length - bytes(searchKey).length; i++) {
            if (bytes(metadata)[i] == bytes(searchKey)[0]) {
                bool isMatch = true;
                for (uint256 j = 0; j < bytes(searchKey).length; j++) {
                    if (bytes(metadata)[i + j] != bytes(searchKey)[j]) {
                        isMatch = false;
                        break;
                    }
                }
                if (isMatch) {
                    startIndex = i + bytes(searchKey).length;
                    break;
                }
            }
        }

        // Assuming you have the logic for calculating endIndex
        // It could be the next comma, semicolon, or end of the metadata, depending on your format
        // For simplicity, let's assume the next double quote after startIndex
        endIndex = getNextDoubleQuoteIndex(metadata, startIndex);

        return substring(metadata, startIndex, endIndex);
    }

    function getNextDoubleQuoteIndex(string memory str, uint256 startIndex) internal pure returns (uint256) {
        for (uint256 i = startIndex; i < bytes(str).length; i++) {
            if (bytes(str)[i] == '"') {
                return i;
            }
        }
        // Return the original endIndex if no double quote is found
        return startIndex;
    }

    function setStatus(uint256 _tokenId, string memory _status) public onlyNFTOwner(_tokenId) {
        require(bytes(_status).length <= MAX_CHARACTER_AMOUNT, "Status exceeds maximum character limit");

        // Get the token URI for the NFT
        string memory tokenURI = getTokenURI(_tokenId);

        // Decode metadata from the token URI
        (string memory name, string memory family) = decodeIPFSMetadata(tokenURI);

        // Update or create status entry
        userStatuses[msg.sender] = StatusInfo(name, family, _status, block.timestamp);
        allStatuses[_tokenId] = StatusInfo(name, family, _status, block.timestamp);

        emit StatusUpdated(name, family, _status, block.timestamp);
    }

    function updateStatus(uint256 _tokenId, string memory _status) public onlyNFTOwner(_tokenId) {
        require(bytes(_status).length <= MAX_CHARACTER_AMOUNT, "Status exceeds maximum character limit");

        // Get the token URI for the NFT
        string memory tokenURI = getTokenURI(_tokenId);

        // Decode metadata from the token URI
        (string memory name, string memory family) = decodeIPFSMetadata(tokenURI);

        // Update status entry
        userStatuses[msg.sender] = StatusInfo(name, family, _status, block.timestamp);
        allStatuses[_tokenId] = StatusInfo(name, family, _status, block.timestamp);

        emit StatusUpdated(name, family, _status, block.timestamp);
    }

    function getStatus(address _user) public view returns (string memory, string memory, string memory) {
        StatusInfo memory statusInfo = userStatuses[_user];
        if (bytes(statusInfo.status).length == 0) {
            return ("", "", "No status set");
        } else {
            return (statusInfo.name, statusInfo.family, statusInfo.status);
        }
    }

    function getAllStatuses(uint256 _tokenId) public view returns (string memory, string memory, string memory, uint256) {
        StatusInfo memory statusInfo = allStatuses[_tokenId];
        if (bytes(statusInfo.status).length == 0) {
            return ("", "", "No status set", 0);
        } else {
            return (statusInfo.name, statusInfo.family, statusInfo.status, statusInfo.timestamp);
        }
    }
}
