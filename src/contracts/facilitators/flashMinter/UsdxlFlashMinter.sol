// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IACLManager} from '@aave/core-v3/contracts/interfaces/IACLManager.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {PercentageMath} from '@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol';
import {IERC3156FlashBorrower} from '@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol';
import {IERC3156FlashLender} from '@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol';
import {IUsdxlToken} from '../../usdxl/interfaces/IUsdxlToken.sol';
import {IUsdxlFacilitator} from '../../usdxl/interfaces/IUsdxlFacilitator.sol';
import {IUsdxlFlashMinter} from './interfaces/IUsdxlFlashMinter.sol';

/**
 * @title GhoFlashMinter
 * @author Aave
 * @notice Contract that enables FlashMinting of GHO.
 * @dev Based heavily on the EIP3156 reference implementation
 */
contract UsdxlFlashMinter is IUsdxlFlashMinter {
  using PercentageMath for uint256;

  // @inheritdoc IUsdxlFlashMinter
  bytes32 public constant CALLBACK_SUCCESS = keccak256('ERC3156FlashBorrower.onFlashLoan');

  // @inheritdoc IUsdxlFlashMinter
  uint256 public constant MAX_FEE = 1e4;

  // @inheritdoc IUsdxlFlashMinter
  IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;

  // @inheritdoc IUsdxlFlashMinter
  IUsdxlToken public immutable USDXL_TOKEN;

  // The Access Control List manager contract
  IACLManager private immutable ACL_MANAGER;

  // The flashmint fee, expressed in bps (a value of 10000 results in 100.00%)
  uint256 private _fee;

  // The GHO treasury, the recipient of fee distributions
  address private _usdxlTreasury;

  /**
   * @dev Only pool admin can call functions marked by this modifier.
   */
  modifier onlyPoolAdmin() {
    require(ACL_MANAGER.isPoolAdmin(msg.sender), 'CALLER_NOT_POOL_ADMIN');
    _;
  }

  /**
   * @dev Constructor
   * @param usdxlToken The address of the GHO token contract
   * @param usdxlTreasury The address of the GHO treasury
   * @param fee The percentage of the flash-mint amount that needs to be repaid, on top of the principal (in bps)
   * @param addressesProvider The address of the Aave PoolAddressesProvider
   */
  constructor(address usdxlToken, address usdxlTreasury, uint256 fee, address addressesProvider) {
    require(fee <= MAX_FEE, 'FlashMinter: Fee out of range');
    USDXL_TOKEN = IUsdxlToken(usdxlToken);
    _updateUsdxlTreasury(usdxlTreasury);
    _updateFee(fee);
    ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider);
    ACL_MANAGER = IACLManager(IPoolAddressesProvider(addressesProvider).getACLManager());
  }

  /// @inheritdoc IERC3156FlashLender
  function flashLoan(
    IERC3156FlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  ) external override returns (bool) {
    require(token == address(USDXL_TOKEN), 'FlashMinter: Unsupported currency');

    uint256 fee = ACL_MANAGER.isFlashBorrower(msg.sender) ? 0 : _flashFee(amount);
    USDXL_TOKEN.mint(address(receiver), amount);

    require(
      receiver.onFlashLoan(msg.sender, address(USDXL_TOKEN), amount, fee, data) == CALLBACK_SUCCESS,
      'FlashMinter: Callback failed'
    );

    USDXL_TOKEN.transferFrom(address(receiver), address(this), amount + fee);
    USDXL_TOKEN.burn(amount);

    emit FlashMint(address(receiver), msg.sender, address(USDXL_TOKEN), amount, fee);

    return true;
  }

  /// @inheritdoc IUsdxlFacilitator
  function distributeFeesToTreasury() external override {
    uint256 balance = USDXL_TOKEN.balanceOf(address(this));
    USDXL_TOKEN.transfer(_usdxlTreasury, balance);
    emit FeesDistributedToTreasury(_usdxlTreasury, address(USDXL_TOKEN), balance);
  }

  // @inheritdoc IUsdxlFlashMinter
  function updateFee(uint256 newFee) external override onlyPoolAdmin {
    _updateFee(newFee);
  }

  /// @inheritdoc IUsdxlFacilitator
  function updateUsdxlTreasury(address newUsdxlTreasury) external override onlyPoolAdmin {
    _updateUsdxlTreasury(newUsdxlTreasury);
  }

  /// @inheritdoc IERC3156FlashLender
  function maxFlashLoan(address token) external view override returns (uint256) {
    if (token != address(USDXL_TOKEN)) {
      return 0;
    } else {
      (uint256 capacity, uint256 level) = USDXL_TOKEN.getFacilitatorBucket(address(this));
      return capacity > level ? capacity - level : 0;
    }
  }

  /// @inheritdoc IERC3156FlashLender
  function flashFee(address token, uint256 amount) external view override returns (uint256) {
    require(token == address(USDXL_TOKEN), 'FlashMinter: Unsupported currency');
    return ACL_MANAGER.isFlashBorrower(msg.sender) ? 0 : _flashFee(amount);
  }

  /// @inheritdoc IUsdxlFlashMinter
  function getFee() external view override returns (uint256) {
    return _fee;
  }

  /// @inheritdoc IUsdxlFacilitator
  function getUsdxlTreasury() external view override returns (address) {
    return _usdxlTreasury;
  }

  /**
   * @notice Returns the fee to charge for a given flashloan.
   * @dev Internal function with no checks.
   * @param amount The amount of tokens to be borrowed.
   * @return The amount of `token` to be charged for the flashloan, on top of the returned principal.
   */
  function _flashFee(uint256 amount) internal view returns (uint256) {
    return amount.percentMul(_fee);
  }

  function _updateFee(uint256 newFee) internal {
    require(newFee <= MAX_FEE, 'FlashMinter: Fee out of range');
    uint256 oldFee = _fee;
    _fee = newFee;
    emit FeeUpdated(oldFee, newFee);
  }

  function _updateUsdxlTreasury(address newUsdxlTreasury) internal {
    address oldUsdxlTreasury = _usdxlTreasury;
    _usdxlTreasury = newUsdxlTreasury;
    emit UsdxlTreasuryUpdated(oldUsdxlTreasury, newUsdxlTreasury);
  }
}
