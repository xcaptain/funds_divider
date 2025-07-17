// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title MyERC20Token
 * @dev A simple ERC20 token similar to USDC with 6 decimal places
 */
contract MyERC20Token is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address owner
    ) ERC20(name, symbol) Ownable(owner) {
        _decimals = 6; // Similar to USDC
        _mint(owner, initialSupply * 10**_decimals);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `6`, a balance of `1000000` tokens should
     * be displayed to a user as `1` token (`1000000 / 10 ** 6`).
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Mint new tokens to a specific address
     * Only the owner can mint new tokens
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint (in token units, not wei)
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount * 10**_decimals);
    }

    /**
     * @dev Burn tokens from a specific address
     * Only the owner can burn tokens
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn (in token units, not wei)
     */
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount * 10**_decimals);
    }

    /**
     * @dev Get the balance of an address in token units (not wei)
     * @param account The address to check the balance of
     * @return The balance in token units
     */
    function balanceOfTokens(address account) public view returns (uint256) {
        return balanceOf(account) / 10**_decimals;
    }
}
