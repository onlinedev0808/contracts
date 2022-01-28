// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./IThirdwebModule.sol";

interface IThirdwebOwnable is IThirdwebModule {
    /// @dev Returns the owner of the contract.
    function owner() external view returns (address);

    /// @dev Lets a module admin set a new owner for the contract. The new owner must be a module admin.
    function setOwner(address _newOwner) external;
}
