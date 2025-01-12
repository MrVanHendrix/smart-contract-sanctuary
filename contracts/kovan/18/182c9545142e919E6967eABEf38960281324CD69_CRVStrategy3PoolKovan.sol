pragma solidity 0.5.16;

import "./CRVStrategy3Pool.sol";

/**
 * This strategy is for the 3CRV vault, i.e., the underlying token is 3CRV. It is not to accept
 * stable coins. It will farm the CRV crop. For liquidation, it swaps CRV into DAI and uses DAI
 * to produce 3CRV.
 */
contract CRVStrategy3PoolKovan is CRVStrategy3Pool {
    constructor(address _storage, address _vault)
        public
        CRVStrategy3Pool(
            _storage,
            _vault,
            address(0), // 3CRV underlying
            address(0), // _gauge
            address(0), // _mintr
            address(0), // _crv
            address(0), // _curve
            address(0xd0A1E359811322d97991E03f863a0C30C2cF029C), // _weth
            address(0x1528F3FCc26d13F7079325Fb78D9442607781c8C), // _dai
            address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f) // _uniswap
        )
    {}
}

pragma solidity 0.5.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../RewardTokenProfitNotifier.sol";
import "../../interfaces/curve/Gauge.sol";
import "../../interfaces/curve/ICurve3Pool.sol";
import "../../interfaces/uniswap/IUniswapV2Router02.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IVault.sol";

contract CRVStrategy3Pool is IStrategy, RewardTokenProfitNotifier {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event Liquidating(uint256 amount);
    event ProfitsNotCollected();

    // 3CRV
    address public underlying;
    address public pool;
    address public mintr;
    address public crv;

    address public curve;
    address public weth;
    address public dai;

    address public uni;

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public unsalvagableTokens;

    address public vault;

    uint256 maxUint = uint256(~0);
    address[] public uniswap_CRV2DAI;

    // a flag for disabling selling for simplified emergency exit
    bool public sell = true;
    // minimum CRV amount to be liquidation
    uint256 public sellFloor = 1e18;

    modifier restricted() {
        require(
            msg.sender == vault ||
                msg.sender == controller() ||
                msg.sender == governance(),
            "The sender has to be the controller, governance, or vault"
        );
        _;
    }

    constructor(
        address _storage,
        address _vault,
        address _underlying,
        address _gauge,
        address _mintr,
        address _crv,
        address _curve,
        address _weth,
        address _dai,
        address _uniswap
    ) public RewardTokenProfitNotifier(_storage, _crv) {
        require(
            IVault(_vault).underlying() == _underlying,
            "vault does not support 3crv"
        );
        vault = _vault;
        underlying = _underlying;
        pool = _gauge;
        mintr = _mintr;
        crv = _crv;
        curve = _curve;
        weth = _weth;
        dai = _dai;
        uni = _uniswap;
        uniswap_CRV2DAI = [crv, weth, dai];
        // set these tokens to be not salvageable
        unsalvagableTokens[underlying] = true;
        unsalvagableTokens[crv] = true;
    }

    function depositArbCheck() public view returns (bool) {
        return true;
    }

    /**
     * Salvages a token. We should not be able to salvage CRV and 3CRV (underlying).
     */
    function salvage(
        address recipient,
        address token,
        uint256 amount
    ) public onlyGovernance {
        // To make sure that governance cannot come in and take away the coins
        require(
            !unsalvagableTokens[token],
            "token is defined as not salvageable"
        );
        IERC20(token).safeTransfer(recipient, amount);
    }

    /**
     * Withdraws 3CRV from the investment pool that mints crops.
     */
    function withdraw3CrvFromPool(uint256 amount) internal {
        Gauge(pool).withdraw(
            Math.min(Gauge(pool).balanceOf(address(this)), amount)
        );
    }

    /**
     * Withdraws the 3CRV tokens to the pool in the specified amount.
     */
    function withdrawToVault(uint256 amountUnderlying) external restricted {
        withdraw3CrvFromPool(amountUnderlying);
        if (IERC20(underlying).balanceOf(address(this)) < amountUnderlying) {
            claimAndLiquidateCrv();
        }
        uint256 toTransfer =
            Math.min(
                IERC20(underlying).balanceOf(address(this)),
                amountUnderlying
            );
        IERC20(underlying).safeTransfer(vault, toTransfer);
    }

    /**
     * Withdraws all the 3CRV tokens to the pool.
     */
    function withdrawAllToVault() external restricted {
        claimAndLiquidateCrv();
        withdraw3CrvFromPool(maxUint);
        uint256 balance = IERC20(underlying).balanceOf(address(this));
        IERC20(underlying).safeTransfer(vault, balance);
    }

    /**
     * Invests all the underlying 3CRV into the pool that mints crops (CRV).
     */
    function investAllUnderlying() public restricted {
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeApprove(pool, 0);
            IERC20(underlying).safeApprove(pool, underlyingBalance);
            Gauge(pool).deposit(underlyingBalance);
        }
    }

    /**
     * Claims the CRV crop, converts it to DAI on Uniswap, and then uses DAI to mint 3CRV using the
     * Curve protocol.
     */
    function claimAndLiquidateCrv() internal {
        if (!sell) {
            // Profits can be disabled for possible simplified and rapid exit
            emit ProfitsNotCollected();
            return;
        }
        Mintr(mintr).mint(pool);

        uint256 rewardBalance = IERC20(crv).balanceOf(address(this));
        if (rewardBalance < sellFloor) {
            // Profits can be disabled for possible simplified and rapid exit
            emit ProfitsNotCollected();
            return;
        }

        notifyProfitInRewardToken(rewardBalance);
        uint256 crvBalance = IERC20(crv).balanceOf(address(this));

        if (crvBalance > 0) {
            emit Liquidating(crvBalance);
            IERC20(crv).safeApprove(uni, 0);
            IERC20(crv).safeApprove(uni, crvBalance);
            // we can accept 1 as the minimum because this will be called only by a trusted worker
            IUniswapV2Router02(uni).swapExactTokensForTokens(
                crvBalance,
                1,
                uniswap_CRV2DAI,
                address(this),
                block.timestamp
            );

            if (IERC20(dai).balanceOf(address(this)) > 0) {
                curve3PoolFromDai();
            }
        }
    }

    /**
     * Claims and liquidates CRV into 3CRV, and then invests all underlying.
     */
    function forceUnleashed() public restricted {
        claimAndLiquidateCrv();
        investAllUnderlying();
    }

    /**
     * Investing all underlying.
     */
    function investedUnderlyingBalance() public view returns (uint256) {
        return
            Gauge(pool).balanceOf(address(this)).add(
                IERC20(underlying).balanceOf(address(this))
            );
    }

    /**
     * Uses the Curve protocol to convert the underlying asset into the mixed token.
     */
    function curve3PoolFromDai() public {
        uint256 daiBalance = IERC20(dai).balanceOf(address(this));
        if (daiBalance > 0) {
            IERC20(dai).safeApprove(curve, 0);
            IERC20(dai).safeApprove(curve, daiBalance);
            uint256 minimum = 0;
            ICurve3Pool(curve).add_liquidity([daiBalance, 0, 0], minimum);
        }
    }

    /**
     * Can completely disable claiming CRV rewards and selling. Good for emergency withdraw in the
     * simplest possible way.
     */
    function setSell(bool s) public onlyGovernance {
        sell = s;
    }

    /**
     * Sets the minimum amount of CRV needed to trigger a sale.
     */
    function setSellFloor(uint256 floor) public onlyGovernance {
        sellFloor = floor;
    }
}

pragma solidity ^0.5.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

pragma solidity ^0.5.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}

pragma solidity ^0.5.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     *
     * _Available since v2.4.0._
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

pragma solidity ^0.5.5;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following 
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    /**
     * @dev Converts an `address` into `address payable`. Note that this is
     * simply a type cast: the actual underlying value is not changed.
     *
     * _Available since v2.4.0._
     */
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     *
     * _Available since v2.4.0._
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

pragma solidity ^0.5.0;

import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for ERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.

        // A Solidity high level call has three parts:
        //  1. The target address is checked to verify it contains contract code
        //  2. The call itself is made, and success asserted
        //  3. The return value is decoded, which in turn checks the size of the returned data.
        // solhint-disable-next-line max-line-length
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IController.sol";
import "../Controllable.sol";

contract RewardTokenProfitNotifier is Controllable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public profitSharingNumerator;
    uint256 public profitSharingDenominator;
    address public rewardToken;

    constructor(address _storage, address _rewardToken)
        public
        Controllable(_storage)
    {
        rewardToken = _rewardToken;
        profitSharingNumerator = 0;
        profitSharingDenominator = 100;
        require(
            profitSharingNumerator < profitSharingDenominator,
            "invalid profit share"
        );
    }

    event ProfitLogInReward(
        uint256 profitAmount,
        uint256 feeAmount,
        uint256 timestamp
    );

    function notifyProfitInRewardToken(uint256 _rewardBalance) internal {
        if (_rewardBalance > 0 && profitSharingNumerator > 0) {
            uint256 feeAmount =
                _rewardBalance.mul(profitSharingNumerator).div(
                    profitSharingDenominator
                );
            emit ProfitLogInReward(_rewardBalance, feeAmount, block.timestamp);
            IERC20(rewardToken).safeApprove(controller(), 0);
            IERC20(rewardToken).safeApprove(controller(), feeAmount);

            IController(controller()).notifyFee(rewardToken, feeAmount);
        } else {
            emit ProfitLogInReward(0, 0, block.timestamp);
        }
    }

    function setProfitSharingNumerator(uint256 _profitSharingNumerator)
        external
        onlyGovernance
    {
        profitSharingNumerator = _profitSharingNumerator;
        require(
            profitSharingNumerator < profitSharingDenominator,
            "invalid profit share"
        );
    }
}

pragma solidity 0.5.16;

interface Gauge {
    function deposit(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256) external;

    function user_checkpoint(address) external;
}

interface VotingEscrow {
    function create_lock(uint256 v, uint256 time) external;

    function increase_amount(uint256 _value) external;

    function increase_unlock_time(uint256 _unlock_time) external;

    function withdraw() external;
}

interface Mintr {
    function mint(address) external;
}

pragma solidity 0.5.16;

interface ICurve3Pool {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount)
        external;

    function remove_liquidity_imbalance(
        uint256[3] calldata amounts,
        uint256 max_burn_amount
    ) external;

    function remove_liquidity(uint256 _amount, uint256[3] calldata amounts)
        external;

    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external;

    function calc_token_amount(uint256[3] calldata amounts, bool deposit)
        external
        view
        returns (uint256);
}

pragma solidity >=0.5.0;

import "./IUniswapV2Router01.sol";

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

pragma solidity 0.5.16;

interface IStrategy {
    function unsalvagableTokens(address tokens) external view returns (bool);

    function governance() external view returns (address);

    function controller() external view returns (address);

    function underlying() external view returns (address);

    function vault() external view returns (address);

    function withdrawAllToVault() external;

    function withdrawToVault(uint256 amount) external;

    function investedUnderlyingBalance() external view returns (uint256); // itsNotMuch()

    // should only be called by controller
    function salvage(
        address recipient,
        address token,
        uint256 amount
    ) external;

    function forceUnleashed() external;

    function depositArbCheck() external view returns (bool);
}

pragma solidity 0.5.16;

interface IVault {
    function underlyingBalanceInVault() external view returns (uint256);

    function underlyingBalanceWithInvestment() external view returns (uint256);

    function governance() external view returns (address);

    function controller() external view returns (address);

    function underlying() external view returns (address);

    function strategy() external view returns (address);

    function setStrategy(address _strategy) external;

    function setVaultFractionToInvest(uint256 numerator, uint256 denominator)
        external;

    function deposit(uint256 amountWei) external;

    function depositFor(uint256 amountWei, address holder) external;

    function withdrawAll() external;

    function withdraw(uint256 numberOfShares) external;

    function getPricePerFullShare() external view returns (uint256);

    function underlyingBalanceWithInvestmentForHolder(address holder)
        external
        view
        returns (uint256);

    // force unleash should be callable only by the controller (by the force unleasher) or by governance
    function forceUnleashed() external;

    function rebalance() external;

    function totalSupplyCap() external view returns (uint256);
}

pragma solidity 0.5.16;

interface IController {
    function whiteList(address _target) external view returns (bool);

    function addVaultAndStrategy(address _vault, address _strategy) external;

    function forceUnleashed(address _vault) external;

    function vaults(address _vault) external view returns (bool);

    function salvage(address _token, uint256 amount) external;

    function salvageStrategy(
        address _strategy,
        address _token,
        uint256 amount
    ) external;

    function notifyFee(address _underlying, uint256 fee) external;

    function profitSharingNumerator() external view returns (uint256);

    function profitSharingDenominator() external view returns (uint256);

    function treasury() external view returns (address);
}

pragma solidity 0.5.16;

import "./Governable.sol";

contract Controllable is Governable {
    constructor(address _storage) public Governable(_storage) {}

    modifier onlyController() {
        require(store.isController(msg.sender), "Not a controller");
        _;
    }

    modifier onlyControllerOrGovernance() {
        require(
            (store.isController(msg.sender) || store.isGovernance(msg.sender)),
            "The caller must be controller or governance"
        );
        _;
    }

    function controller() public view returns (address) {
        return store.controller();
    }
}

pragma solidity 0.5.16;

import "./Storage.sol";

contract Governable {
    Storage public store;

    constructor(address _store) public {
        require(_store != address(0), "new storage shouldn't be empty");
        store = Storage(_store);
    }

    modifier onlyGovernance() {
        require(store.isGovernance(msg.sender), "Not governance");
        _;
    }

    function setStorage(address _store) public onlyGovernance {
        require(_store != address(0), "new storage shouldn't be empty");
        store = Storage(_store);
    }

    function governance() public view returns (address) {
        return store.governance();
    }
}

pragma solidity 0.5.16;

contract Storage {
    address public governance;
    address public controller;

    constructor() public {
        governance = msg.sender;
    }

    modifier onlyGovernance() {
        require(isGovernance(msg.sender), "Not governance");
        _;
    }

    function setGovernance(address _governance) public onlyGovernance {
        require(_governance != address(0), "new governance shouldn't be empty");
        governance = _governance;
    }

    function setController(address _controller) public onlyGovernance {
        require(_controller != address(0), "new controller shouldn't be empty");
        controller = _controller;
    }

    function isGovernance(address account) public view returns (bool) {
        return account == governance;
    }

    function isController(address account) public view returns (bool) {
        return account == controller;
    }
}

pragma solidity >=0.5.0;

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

{
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "libraries": {}
}