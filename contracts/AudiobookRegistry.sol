// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Audiobook Registry
 * @author Bubble Protocol
 *
 * Maintains a register of published audiobooks for discovery purposes.
 */
contract AudiobookRegistry {

  event Register( address indexed author, address indexed bubbleContract );
  event Deregister( address indexed author, address indexed bubbleContract );

  function register( address bubbleContract ) public {
    emit Register(msg.sender, bubbleContract);
  }

  function deregister( address bubbleContract ) public {
    emit Deregister(msg.sender, bubbleContract);
  }

}
