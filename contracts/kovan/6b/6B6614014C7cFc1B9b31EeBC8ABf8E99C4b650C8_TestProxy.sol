// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import {TransferHelper} from "@uniswap/lib/contracts/libraries/TransferHelper.sol";

enum PoolSpecialization { GENERAL, MINIMAL_SWAP_INFO, TWO_TOKEN }

interface LBPFactory {
    function create(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory weights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart
    ) external returns (address);
}

interface Vault {
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external;

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external;
}

interface LBP {
    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external;

    function setSwapEnabled(bool swapEnabled) external;

    function getPoolId() external returns (bytes32 poolID);
}

contract TestProxy {
    address public constant VaultAddress = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    mapping(address => address) public poolOwner;

    address public immutable feeRecipient;
    address public immutable LBPFactoryAddress;

    constructor(address _feeRecipient, address _LBPFactoryAddress) {
        feeRecipient = _feeRecipient;
        LBPFactoryAddress = _LBPFactoryAddress;
    }

    struct PoolConfig {
        string name;
        string symbol;
        address[] tokens;
        uint256[] amounts;
        uint256[] weights;
        uint256 swapFeePercentage;
        address owner;
        bool fromInternalBalance;
        uint256 startTime;
        uint256 endTime;
        uint256[] endWeights;
    }

    function createAuction(PoolConfig memory poolConfig) external {

        // 1: deposit tokens and approve vault
        // TODO 

        // 2: pool creation
        address pool = LBPFactory(LBPFactoryAddress).create(
            poolConfig.name,
            poolConfig.symbol,
            poolConfig.tokens,
            poolConfig.weights,
            poolConfig.swapFeePercentage,
            address(this), // owner set to this proxy
            false // swaps disabled on start
        );
        poolOwner[pool] = poolConfig.owner;

        // // 3: deposit tokens into pool
        // Vault(VaultAddress).joinPool(
        //     LBP(pool).getPoolId(),
        //     address(this), // todo: check if can remove token approvals by changing this value
        //     address(this), // todo: check if correct recipient
        //     Vault.JoinPoolRequest(
        //         poolConfig.tokens,
        //         poolConfig.amounts,
        //         "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000008ac7230489e800000000000000000000000000000000000000000000000000000011c37937e08000”,,
        //         poolConfig.fromInternalBalance
        //     )
        // );

        // 4: configure weights
        LBP(pool).updateWeightsGradually(
            poolConfig.startTime,
            poolConfig.endTime,
            poolConfig.endWeights
        );
    }

    function setSwapEnabled(address pool, bool swapEnabled) external {
        LBP(pool).setSwapEnabled(swapEnabled);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.6.0;

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeApprove: approve failed'
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeTransfer: transfer failed'
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::transferFrom: transferFrom failed'
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }
}