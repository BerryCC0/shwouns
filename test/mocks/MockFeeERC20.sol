// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Fee-on-transfer token: every transfer delivers (amount - fee) and burns the fee, so the
///      recipient receives less than `amount`. Used to prove M-04 balance-delta accounting.
contract MockFeeERC20 is ERC20 {
    uint256 public immutable feeBps;

    constructor(uint256 _feeBps) ERC20("FeeToken", "FEE") {
        feeBps = _feeBps;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount); // minting takes no fee
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 fee = (amount * feeBps) / 10000;
        super._transfer(from, to, amount - fee);
        if (fee > 0) _burn(from, fee);
    }
}
