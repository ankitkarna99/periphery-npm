// Neptune Mutual Protocol (https://neptunemutual.com)
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "./IMember.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IVault is IMember, IERC20Upgradeable {
  struct VaultInfoType {
    uint256 totalPods;
    uint256 balance;
    uint256 extendedBalance;
    uint256 totalReassurance;
    uint256 myPodBalance;
    uint256 myShare;
    uint256 withdrawalOpen;
    uint256 withdrawalClose;
  }

  struct AddLiquidityArgs {
    bytes32 coverKey;
    uint256 amount;
    uint256 npmStakeToAdd;
    bytes32 referralCode;
  }

  event GovernanceTransfer(address indexed to, uint256 amount);
  event StrategyTransfer(address indexed token, address indexed strategy, bytes32 indexed name, uint256 amount);
  event StrategyReceipt(address indexed token, address indexed strategy, bytes32 indexed name, uint256 amount, uint256 income, uint256 loss);
  event PodsIssued(address indexed account, uint256 issued, uint256 liquidityAdded, bytes32 indexed referralCode);
  event PodsRedeemed(address indexed account, uint256 redeemed, uint256 liquidityReleased);
  event FlashLoanBorrowed(address indexed lender, address indexed borrower, address indexed stablecoin, uint256 amount, uint256 fee);
  event NpmStaken(address indexed account, uint256 amount);
  event NpmUnstaken(address indexed account, uint256 amount);
  event InterestAccrued(bytes32 indexed coverKey);
  event Entered(bytes32 indexed coverKey, address indexed account);
  event Exited(bytes32 indexed coverKey, address indexed account);

  function key() external view returns (bytes32);

  function sc() external view returns (address);

  function addLiquidity(AddLiquidityArgs calldata args) external;
  function accrueInterest() external;
  function removeLiquidity(bytes32 coverKey, uint256 amount, uint256 npmStake, bool exit) external;

  function transferGovernance(bytes32 coverKey, address to, uint256 amount) external;

  function transferToStrategy(IERC20Upgradeable token, bytes32 coverKey, bytes32 strategyName, uint256 amount) external;
  function receiveFromStrategy(IERC20Upgradeable token, bytes32 coverKey, bytes32 strategyName, uint256 amount) external;

  function calculatePods(uint256 forStablecoinUnits) external view returns (uint256);
  function calculateLiquidity(uint256 podsToBurn) external view returns (uint256);

  function getInfo(address forAccount) external view returns (VaultInfoType memory info);
  function getStablecoinBalanceOf() external view returns (uint256);
}
