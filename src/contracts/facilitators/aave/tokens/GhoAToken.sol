// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {GPv2SafeERC20} from '@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {VersionedInitializable} from '@aave/core-v3/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol';
import {Errors} from '@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol';
import {WadRayMath} from '@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IAToken} from '@aave/core-v3/contracts/interfaces/IAToken.sol';
import {IAaveIncentivesController} from '@aave/core-v3/contracts/interfaces/IAaveIncentivesController.sol';
import {IInitializableAToken} from '@aave/core-v3/contracts/interfaces/IInitializableAToken.sol';
import {ScaledBalanceTokenBase} from '@aave/core-v3/contracts/protocol/tokenization/base/ScaledBalanceTokenBase.sol';
import {IncentivizedERC20} from '@aave/core-v3/contracts/protocol/tokenization/base/IncentivizedERC20.sol';
import {EIP712Base} from '@aave/core-v3/contracts/protocol/tokenization/base/EIP712Base.sol';

// Gho Imports
import {IUsdxlToken} from '../../../gho/interfaces/IGhoToken.sol';
import {IUsdxlFacilitator} from '../../../gho/interfaces/IGhoFacilitator.sol';
import {IUsdxlAToken} from './interfaces/IGhoAToken.sol';
import {UsdxlVariableDebtToken} from './GhoVariableDebtToken.sol';

/**
 * @title GhoAToken
 * @author Aave
 * @notice Implementation of the interest bearing token for the Aave protocol
 */
contract UsdxlAToken is VersionedInitializable, ScaledBalanceTokenBase, EIP712Base, IUsdxlAToken {
  using WadRayMath for uint256;
  using GPv2SafeERC20 for IERC20;

  bytes32 public constant PERMIT_TYPEHASH =
    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

  uint256 public constant ATOKEN_REVISION = 0x1;

  address internal _treasury;
  address internal _underlyingAsset;

  // Gho Storage
  UsdxlVariableDebtToken internal _usdxlVariableDebtToken;
  address internal _usdxlTreasury;

  /// @inheritdoc VersionedInitializable
  function getRevision() internal pure virtual override returns (uint256) {
    return ATOKEN_REVISION;
  }

  /**
   * @dev Constructor.
   * @param pool The address of the Pool contract
   */
  constructor(
    IPool pool
  ) ScaledBalanceTokenBase(pool, 'USDXL_ATOKEN_IMPL', 'USDXL_ATOKEN_IMPL', 0) EIP712Base() {
    // Intentionally left blank
  }

  /// @inheritdoc IInitializableAToken
  function initialize(
    IPool initializingPool,
    address treasury,
    address underlyingAsset,
    IAaveIncentivesController incentivesController,
    uint8 aTokenDecimals,
    string calldata aTokenName,
    string calldata aTokenSymbol,
    bytes calldata params
  ) external override initializer {
    require(initializingPool == POOL, Errors.POOL_ADDRESSES_DO_NOT_MATCH);
    _setName(aTokenName);
    _setSymbol(aTokenSymbol);
    _setDecimals(aTokenDecimals);

    _treasury = treasury;
    _underlyingAsset = underlyingAsset;
    _incentivesController = incentivesController;

    _domainSeparator = _calculateDomainSeparator();

    emit Initialized(
      underlyingAsset,
      address(POOL),
      treasury,
      address(incentivesController),
      aTokenDecimals,
      aTokenName,
      aTokenSymbol,
      params
    );
  }

  /// @inheritdoc IAToken
  function mint(
    address caller,
    address onBehalfOf,
    uint256 amount,
    uint256 index
  ) external virtual override onlyPool returns (bool) {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  /// @inheritdoc IAToken
  function burn(
    address from,
    address receiverOfUnderlying,
    uint256 amount,
    uint256 index
  ) external virtual override onlyPool {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  /// @inheritdoc IAToken
  function mintToTreasury(uint256 amount, uint256 index) external virtual override onlyPool {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  /// @inheritdoc IAToken
  function transferOnLiquidation(
    address from,
    address to,
    uint256 value
  ) external virtual override onlyPool {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  /// @inheritdoc IERC20
  function balanceOf(
    address user
  ) public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
    return 0;
  }

  /// @inheritdoc IERC20
  function totalSupply() public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
    return 0;
  }

  /// @inheritdoc IAToken
  function RESERVE_TREASURY_ADDRESS() external view override returns (address) {
    return _treasury;
  }

  /// @inheritdoc IAToken
  function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
    return _underlyingAsset;
  }

  /**
   * @notice Transfers the underlying asset to `target`.
   * @dev It performs a mint of GHO on behalf of the `target`
   * @dev Used by the Pool to transfer assets in borrow(), withdraw() and flashLoan()
   * @param target The recipient of the underlying
   * @param amount The amount getting transferred
   */
  function transferUnderlyingTo(address target, uint256 amount) external virtual override onlyPool {
    IUsdxlToken(_underlyingAsset).mint(target, amount);
  }

  /// @inheritdoc IAToken
  function handleRepayment(
    address user,
    address onBehalfOf,
    uint256 amount
  ) external virtual override onlyPool {
    uint256 balanceFromInterest = _usdxlVariableDebtToken.getBalanceFromInterest(onBehalfOf);
    if (amount <= balanceFromInterest) {
      _usdxlVariableDebtToken.decreaseBalanceFromInterest(onBehalfOf, amount);
    } else {
      _usdxlVariableDebtToken.decreaseBalanceFromInterest(onBehalfOf, balanceFromInterest);
      IUsdxlToken(_underlyingAsset).burn(amount - balanceFromInterest);
    }
  }

  /// @inheritdoc IUsdxlFacilitator
  function distributeFeesToTreasury() external virtual override {
    uint256 balance = IERC20(_underlyingAsset).balanceOf(address(this));
    IERC20(_underlyingAsset).transfer(_usdxlTreasury, balance);
    emit FeesDistributedToTreasury(_usdxlTreasury, _underlyingAsset, balance);
  }

  /// @inheritdoc IAToken
  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external override {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  /**
   * @notice Overrides the parent _transfer to force validated transfer() and transferFrom()
   * @param from The source address
   * @param to The destination address
   * @param amount The amount getting transferred
   */
  function _transfer(address from, address to, uint128 amount) internal override {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  /**
   * @dev Overrides the base function to fully implement IAToken
   * @dev see `EIP712Base.DOMAIN_SEPARATOR()` for more detailed documentation
   */
  function DOMAIN_SEPARATOR() public view override(IAToken, EIP712Base) returns (bytes32) {
    return super.DOMAIN_SEPARATOR();
  }

  /**
   * @dev Overrides the base function to fully implement IAToken
   * @dev see `EIP712Base.nonces()` for more detailed documentation
   */
  function nonces(address owner) public view override(IAToken, EIP712Base) returns (uint256) {
    return super.nonces(owner);
  }

  /// @inheritdoc EIP712Base
  function _EIP712BaseId() internal view override returns (string memory) {
    return name();
  }

  /// @inheritdoc IAToken
  function rescueTokens(address token, address to, uint256 amount) external override onlyPoolAdmin {
    require(token != _underlyingAsset, Errors.UNDERLYING_CANNOT_BE_RESCUED);
    IERC20(token).safeTransfer(to, amount);
  }

  /// @inheritdoc IUsdxlAToken
  function setVariableDebtToken(address usdxlVariableDebtToken) external override onlyPoolAdmin {
    require(address(_usdxlVariableDebtToken) == address(0), 'VARIABLE_DEBT_TOKEN_ALREADY_SET');
    require(usdxlVariableDebtToken != address(0), 'ZERO_ADDRESS_NOT_VALID');
    _usdxlVariableDebtToken = UsdxlVariableDebtToken(usdxlVariableDebtToken);
    emit VariableDebtTokenSet(usdxlVariableDebtToken);
  }

  /// @inheritdoc IUsdxlAToken
  function getVariableDebtToken() external view override returns (address) {
    return address(_usdxlVariableDebtToken);
  }

  /// @inheritdoc IUsdxlFacilitator
  function updateUsdxlTreasury(address newUsdxlTreasury) external override onlyPoolAdmin {
    require(newUsdxlTreasury != address(0), 'ZERO_ADDRESS_NOT_VALID');
    address oldUsdxlTreasury = _usdxlTreasury;
    _usdxlTreasury = newUsdxlTreasury;
    emit UsdxlTreasuryUpdated(oldUsdxlTreasury, newUsdxlTreasury);
  }

  /// @inheritdoc IUsdxlFacilitator
  function getUsdxlTreasury() external view override returns (address) {
    return _usdxlTreasury;
  }
}
