// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SDAC.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";


// Default files
address constant PUBLIC_METADATA_FILE = address(0x80000000000000000000000000000001);
address constant PUBLIC_DIRECTORY = address(0x80000000000000000000000000000002);
address constant NFT_OWNERS_ONLY_DIRECTORY = address(0x80000000000000000000000000000003);


/**
 * @title Audiobook NFT-controlled SDAC
 * @author Bubble Protocol
 *
 * Provides read access for owners of an NFT.  Each NFT owner has read access to a public directory and to a file 
 * named after their token ID.  Everyone has access to a public metadata file and a public directory. 
 */
contract AudiobookSDAC is SDAC {

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
    function getPermissions( address requester, address file ) public override view returns (bytes1) {
        bytes1 directoryBit = (file == PUBLIC_METADATA_FILE) ? bytes1(0) : DIRECTORY_BIT;
        if (requester == owner) return directoryBit | READ_BIT | WRITE_BIT | APPEND_BIT;
        if (file == PUBLIC_METADATA_FILE) return READ_BIT;
        if (file == PUBLIC_DIRECTORY) return DIRECTORY_BIT | READ_BIT;
        bool requesterHasNft = nftContract.balanceOf(requester) > 0;
        if (requesterHasNft && file == NFT_OWNERS_ONLY_DIRECTORY) return DIRECTORY_BIT | READ_BIT;
        if (requesterHasNft && file == requester) return DIRECTORY_BIT | READ_BIT;
        return NO_PERMISSIONS;
    }

    /**
     * @dev returns true if the contract has expired either automatically or has been manually terminated
     * Depreciated.  Future versions of datona-lib will use getState() === 0
     */
    function hasExpired() public override view returns (bool) {
        return terminated;
    }

    /**
     * @dev terminates the contract if the sender is permitted and any termination conditions are met
     */
    function terminate() public override {
        require(msg.sender == owner);
        terminated = true;
    }
    
}
