// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControlledStorage.sol";
import "./AccessControlBits.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";


// Default files
uint constant PUBLIC_METADATA_FILE = 0x8000000000000000000000000000000000000000000000000000000000000001;
uint constant PUBLIC_DIRECTORY = 0x8000000000000000000000000000000000000000000000000000000000000002;
uint constant NFT_OWNERS_ONLY_DIRECTORY = 0x8000000000000000000000000000000000000000000000000000000000000003;


/**
 * @title Audiobook NFT-controlled SDAC
 * @author Bubble Protocol
 *
 * Provides read access for owners of an NFT.  Each NFT owner has read access to a public directory and to a file 
 * named after their token ID.  Everyone has access to a public metadata file and a public directory. 
 */
contract AudiobookACC is AccessControlledStorage {

    address public owner = msg.sender;
    bool private terminated = false;
    IERC721 public nftContract;

    /**
     * @dev Constructs the SDAC controlled by the given NFT contract.  Sets the owner to proxyOwner
     */
    constructor(IERC721 nft) {
        nftContract = nft;
    }

    /**
     * @dev Used by a vault server to get the drwa permissions for the given file and requester
     *
     * - Each token has a corresponding directory within the bubble named after the token id
     * - There is a single public metadata file and public directory at the addresses defined above
     * - Owner has rwa access to all files/directories
     * - Token holders have read access to a token directory if they own the token
     * - Token holders (of any series) have access to the single "owner's" directory defined above
     */
    function getAccessPermissions( address user, uint256 contentId ) override external view returns (uint256) {
        if (terminated) return BUBBLE_TERMINATED_BIT;
        uint directoryBit = (contentId == PUBLIC_METADATA_FILE) ? 0 : DIRECTORY_BIT;
        if (user == owner) return directoryBit | RWA_BITS;
        if (contentId == PUBLIC_METADATA_FILE) return READ_BIT;
        if (contentId == PUBLIC_DIRECTORY) return DIRECTORY_BIT | READ_BIT;
        bool requesterHasNft = nftContract.balanceOf(user) > 0;
        if (requesterHasNft && contentId == NFT_OWNERS_ONLY_DIRECTORY) return DIRECTORY_BIT | READ_BIT;
        if (requesterHasNft && contentId == uint(uint160(user))) return DIRECTORY_BIT | READ_BIT;
        return NO_PERMISSIONS;
    }

    /**
     * @dev terminates the contract if the sender is permitted and any termination conditions are met
     */
    function terminate() public {
        require(msg.sender == owner);
        terminated = true;
    }
    
}
