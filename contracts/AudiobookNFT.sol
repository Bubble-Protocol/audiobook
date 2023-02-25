pragma solidity ^0.8.0;
pragma abicoder v2;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


/**
 * @title AudiobookNFT
 * @author Bubble Protocol
 *
 * This ERC721 contract will extend OpenZeppelin's ERC721 implementation with features required for the
 * Audiobook application.
 * 
 */

contract AudiobookNFT is ERC721 {

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_)
      ERC721(name_, symbol_) {}

}