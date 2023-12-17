// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

contract BullStatus {
    uint256 constant MAX_CHARACTER_AMOUNT = 134;

    mapping(address => string) public statuses;
    event StatusUpdated(address indexed user, string newStatus, uint256 timestamp);

    function setStatus(string memory _status) public {
        require(bytes(_status).length <= MAX_CHARACTER_AMOUNT, "Status More than BULLs");

        statuses[msg.sender] = _status;

        emit StatusUpdated(msg.sender, _status, block.timestamp);
    }

    function getStatus(address _user) public view returns (string memory) {
        string memory status = statuses[_user];
        if (bytes(status).length == 0) {
            return "No status set";
        } else {
            return status;
        }
    }

    function getAllStatuses() public view returns (address[] memory, string[] memory) {
        uint256 totalUsers = addressCount();
        address[] memory allUsers = new address[](totalUsers);
        string[] memory allStatuses = new string[](totalUsers);

        for (uint256 i = 0; i < totalUsers; i++) {
            address user = allUsers[i];
            allUsers[i] = user;
            allStatuses[i] = getStatus(user);
        }

        return (allUsers, allStatuses);
    }

    function addressCount() public view returns (uint256) {
        // A separate function to count the number of addresses with statuses
        uint256 count = 0;
        for (uint256 i = 0; i < addressCount(); i++) {
            if (bytes(getStatus(allUsers[i])).length > 0) {
                count++;
            }
        }
        return count;
    }
}
