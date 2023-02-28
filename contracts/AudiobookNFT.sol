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
   * @dev Author of the audiobook
   */
  address public author = _msgSender();

  /**
   * @dev Price of this audiobook in wei
   */
  uint256 public price;

  /**
   * @dev Number of audiobooks minted
   */
  uint256 public numberOfTokensMinted;

  /**
   * @dev Initializes the contract by setting a `name`, `symbol` and `price` to the token collection.
   */
  constructor(string memory name_, string memory symbol_, uint256 price_)
    ERC721(name_, symbol_) 
    {
      price = price_;
    }

  /**
   * @dev Set the mint `price` of this nft in wei (owner only)
   */
  function setPrice(uint256 newPrice_) public {
    require(_msgSender() == author, "permission denied"); 
    price = newPrice_;
  }

  /**
   * @dev Allows anyone to buy an audiobook.  
   * @return the token id.
   */
  function mintToken() public virtual payable returns (uint256) {
    require(msg.value >= price, "payment insufficient"); 
    _mint(_msgSender(), numberOfTokensMinted);
    return numberOfTokensMinted++;
  }

  /**
   * @dev Withdraw the given amount of wei to the owner's account (owner only)
   */
  function withdraw(uint256 amount_) public {
    require(_msgSender() == author, "permission denied"); 
    require(amount_ <= address(this).balance, "insufficient balance"); 
    payable(author).transfer(amount_);
  }

}