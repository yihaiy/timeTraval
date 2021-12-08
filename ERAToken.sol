//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
import "./ERC20/ERC20.sol";


contract ERAToken is ERC20 {

    uint256 private maxSupply = 24000000 * 10 ** 18;

	constructor() ERC20("ERA Token","ERA", 18, maxSupply) {
	    _mint(msg.sender, maxSupply);
	}
	
}