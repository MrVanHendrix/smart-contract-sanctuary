// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./TokenStand.sol";

interface IMigratorFarm {
    // Take the current LP token addresss and return the new LP token address.
    // Migration should have full access to the caller's LP token.
    function migrate(IERC20 token) external returns (IERC20);
}

contract MasterChef is IERC721Receiver, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    // Info of each farm.
    struct FarmInfo {
        address stakingToken; // Address of staking token contract.
        bool isNft;
        uint256 allocPoint; // How many allocation points assigned to this farm. STANDs to distribute per block.
        uint256 lastRewardBlock; // Last block number that STANDs distribution occurs.
        uint256 accStandPerShare; // Accumulated STANDs per share, times 1e12. See below.
        IERC20 gift; // Address of gift token contract.
        uint256 scale;
        uint256 duration;
        address rewardDistribution;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    // @notice The migrator contract. It has a lot of power.
    IMigratorFarm public migrator;

    // The STAND TOKEN!
    TokenStand public stand;
    // Dev address.
    address public devaddr;
    // STAND tokens created per block.
    uint256 public standPerBlock;

    /// @notice Info of each farm.
    FarmInfo[] public farmInfo;
    /// @notice Address of the staking token for each pool.
    address[] public stakingTokens;
    /// @notice Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    /// @dev The block number when STAND mining starts.
    uint256 public startBlock;

    event StakedLP(
        address indexed user,
        uint256 indexed fid,
        uint256 amount,
        uint256 standAmount,
        uint256 rewardAmount
    );
    event StakedSingleNft(
        address indexed user,
        uint256 indexed fid,
        uint256 tokenId,
        uint256 standAmount
    );
    event StakedBatchNft(
        address indexed user,
        uint256 indexed fid,
        uint256[] tokenIds,
        uint256 standAmount
    );
    event WithdrawnLP(
        address indexed user,
        uint256 indexed fid,
        uint256 amount,
        uint256 standAmount,
        uint256 rewardAmount
    );
    event WithdrawnSingleNft(
        address indexed user,
        uint256 indexed fid,
        uint256 tokenId,
        uint256 standAmount
    );
    event WithdrawnBatchNft(
        address indexed user,
        uint256 indexed fid,
        uint256[] tokenIds,
        uint256 standAmount
    );
    event ClaimRewardInNftPool(
        address indexed user,
        uint256 indexed fid,
        uint256 standAmount
    );
    event EmergencyWithdrawLP(
        address indexed user,
        uint256 indexed fid,
        uint256 amount
    );
    event EmergencyWithdrawNft(
        address indexed user,
        uint256 indexed fid,
        uint256[] tokenIds
    );
    event LogFarmAddition(
        uint256 indexed fid,
        uint256 allocPoint,
        address indexed stakingToken,
        bool isNft,
        IERC20 indexed gift,
        uint256 duration,
        address rewardDistribution,
        uint256 scale
    );
    event LogSetFarm(uint256 indexed fid, uint256 allocPoint);
    event LogUpdateFarm(
        uint256 indexed fid,
        uint256 lastRewardBlock,
        uint256 lpSupply,
        uint256 accStandPerShare
    );
    event DurationUpdated(uint256 indexed fid, uint256 duration);
    event ScaleUpdated(uint256 indexed fid, uint256 scale);
    event RewardAdded(uint256 indexed fid, IERC20 indexed gift, uint256 amount);
    event RewardDistributionChanged(
        uint256 indexed fid,
        address indexed rewardDistribution
    );

    constructor(
        TokenStand _stand,
        address _devAddr,
        uint256 _standPerBlock,
        uint256 _startBlock
    ) public {
        stand = _stand;
        devaddr = _devAddr;
        standPerBlock = _standPerBlock;
        startBlock = _startBlock;
    }

    // Returns the number of farms.
    function farmLength() public view returns (uint256 farms) {
        farms = farmInfo.length;
    }

    /// @notice Set the `migrator` contract. Can only be called by the owner.
    /// @param _migrator The contract address to set.
    function setMigrator(IMigratorFarm _migrator) public onlyOwner {
        migrator = _migrator;
    }

    /// @notice Migrate LP token to another LP contract through the `migrator` contract.
    /// @notice ONLY FOR ERC20 LP Token!
    /// @param _fid The index of the farm. See `farmInfo`.
    function migrate(uint256 _fid) public {
        require(
            address(migrator) != address(0),
            "TokenStand Farming: no migrator set"
        );
        IERC20 _lpToken = IERC20(stakingTokens[_fid]);
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(_lpToken);
        require(
            bal == newLpToken.balanceOf(address(this)),
            "TokenStand Farming: migrated balance must match"
        );
        stakingTokens[_fid] = address(newLpToken);
    }

    /// @notice Add a new Farm. Can only be called by the owner.
    /// DO NOT add the same Staking token more than once. Rewards will be messed up if you do.
    function addFarm(
        uint256 _allocPoint,
        address _stakingToken,
        bool _isNft,
        IERC20 _gift,
        uint256 _duration,
        address _rewardDistribution,
        uint256 _scale,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdateFarms();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        stakingTokens.push(_stakingToken);

        if (address(_gift) != address(0)) {
            require(
                !_isNft,
                "TokenStand Farming: cannot add gift in erc721 farming pool"
            );
            require(_scale > 0, "TokenStand Farming: scale is too low");
            require(_scale <= 1e36, "TokenStand Farming: scale is too high");
            uint256 len = farmLength();
            for (uint256 i = 0; i < len; i++) {
                require(
                    address(_gift) != stakingTokens[i],
                    "TokenStand Farming: gift is already added"
                );
            }
        }

        farmInfo.push(
            FarmInfo({
                stakingToken: _stakingToken,
                isNft: _isNft,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accStandPerShare: 0,
                gift: _gift,
                scale: _scale,
                duration: _duration,
                rewardDistribution: _rewardDistribution,
                periodFinish: 0,
                rewardRate: 0,
                lastUpdateTime: 0,
                rewardPerTokenStored: 0
            })
        );

        emit LogFarmAddition(
            stakingTokens.length.sub(1),
            _allocPoint,
            _stakingToken,
            _isNft,
            _gift,
            _duration,
            _rewardDistribution,
            _scale
        );
    }

    /// @notice Update the given farm's STAND allocation point. Can only be called by the owner.
    /// @param fids The array of index of the farm. See `farmInfo`.
    /// @param allocPoints Array of New APs of the farm.
    function set(
        uint256[] memory fids,
        uint256[] memory allocPoints,
        bool withUpdate
    ) public onlyOwner {
        require(
            fids.length == allocPoints.length,
            "invalid fids/allocPoints length"
        );

        if (withUpdate) {
            massUpdateFarms();
        }

        for (uint256 i = 0; i < fids.length; i++) {
            uint256 prevAllocPoint = farmInfo[fids[i]].allocPoint;
            farmInfo[fids[i]].allocPoint = allocPoints[i];
            if (prevAllocPoint != allocPoints[i]) {
                totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(
                    allocPoints[i]
                );
            }
            emit LogSetFarm(fids[i], allocPoints[i]);
        }
    }

    /// @notice View function to see pending STAND on frontend.
    /// @param fid The index of the farm. See `farmInfo`.
    /// @param account Address of user.
    /// @return pending STAND reward for a given user.
    function pendingStand(uint256 fid, address account)
        external
        view
        returns (uint256 pending)
    {
        FarmInfo memory farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][account];
        uint256 accStandPerShare = farm.accStandPerShare;
        uint256 stakingSupply = farm.isNft
            ? IERC721(stakingTokens[fid]).balanceOf(address(this))
            : IERC20(stakingTokens[fid]).balanceOf(address(this));
        if (block.number > farm.lastRewardBlock && stakingSupply != 0) {
            uint256 blocks = block.number.sub(farm.lastRewardBlock);
            uint256 standReward = blocks
                .mul(standPerBlock)
                .mul(farm.allocPoint)
                .div(totalAllocPoint);
            accStandPerShare = accStandPerShare.add(
                standReward.mul(1e12).div(stakingSupply)
            );
        }
        pending = user.amount.mul(accStandPerShare).div(1e12).sub(
            user.rewardDebt
        );
    }

    /// @notice View function to see pending gift on frontend.
    /// @param fid The index of the farm. See `farmInfo`.
    /// @param account Address of user.
    /// @return pending gift reward for a given user.
    function pendingGift(uint256 fid, address account)
        public
        view
        returns (uint256 pending)
    {
        FarmInfo memory farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][account];
        pending = user
            .amount
            .mul(rewardPerToken(fid).sub(user.userRewardPerTokenPaid))
            .div(farm.scale)
            .add(user.rewards);
    }

    /// @notice Update reward variables for all farms. Be careful of gas spending!
    function massUpdateFarms() public {
        uint256 len = farmInfo.length;
        for (uint256 fid = 0; fid < len; ++fid) {
            updateFarm(fid, address(0));
        }
    }

    /// @notice Update reward variables of the given farm.
    /// @param fid The index of the farm. See `farmInfo`.
    /// @param account The address is updating farm infor.
    function updateFarm(uint256 fid, address account) public {
        FarmInfo storage farm = farmInfo[fid];

        if (address(farm.gift) != address(0) && !farm.isNft) {
            uint256 newRewardPerToken = rewardPerToken(fid);
            farm.rewardPerTokenStored = newRewardPerToken;
            farm.lastUpdateTime = lastTimeRewardApplicable(fid);

            if (account != address(0)) {
                UserInfo storage user = userInfo[fid][msg.sender];

                user.rewards = pendingGift(fid, account);
                user.userRewardPerTokenPaid = newRewardPerToken;
            }
        }

        uint256 stakingSupply = farm.isNft
            ? IERC721(stakingTokens[fid]).balanceOf(address(this))
            : IERC20(stakingTokens[fid]).balanceOf(address(this));
        if (block.number > farm.lastRewardBlock) {
            if (stakingSupply > 0) {
                uint256 blocks = block.number.sub(farm.lastRewardBlock);
                uint256 standReward = blocks
                    .mul(standPerBlock)
                    .mul(farm.allocPoint)
                    .div(totalAllocPoint);
                stand.mint(devaddr, standReward.mul(15).div(100));
                stand.mint(address(this), standReward);
                farm.accStandPerShare = farm.accStandPerShare.add(
                    standReward.mul(1e12).div(stakingSupply)
                );
            }
            farm.lastRewardBlock = block.number;
        }
        emit LogUpdateFarm(
            fid,
            farm.lastRewardBlock,
            stakingSupply,
            farm.accStandPerShare
        );
    }

    // Deposit ERC20 LP token to MasterChef for STAND (and Gift) allocation
    function stakeLP(uint256 fid, uint256 amount) external nonReentrant {
        FarmInfo storage farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][msg.sender];

        require(
            !farm.isNft,
            "TokenStand Farming: invalid staking token for this farming pool"
        );

        updateFarm(fid, msg.sender);

        uint256 standReward = 0;
        uint256 giftReward = 0;

        if (user.amount > 0) {
            standReward = user.amount.mul(farm.accStandPerShare).div(1e12).sub(
                user.rewardDebt
            );
            giftReward = user.rewards;
            if (standReward > 0) {
                safeStandTransfer(msg.sender, standReward);
            }
            if (giftReward > 0) {
                user.rewards = 0;
                farm.gift.safeTransfer(msg.sender, giftReward);
            }
        }
        if (amount > 0) {
            IERC20(stakingTokens[fid]).safeTransferFrom(
                address(msg.sender),
                address(this),
                amount
            );
            user.amount = user.amount.add(amount);
        }

        user.rewardDebt = user.amount.mul(farm.accStandPerShare).div(1e12);
        emit StakedLP(msg.sender, fid, amount, standReward, giftReward);
    }

    // Deposit single NFT token to MasterChef for STAND (and Gift) allocation
    function stakeSingleNft(uint256 fid, uint256 tokenId)
        external
        nonReentrant
    {
        FarmInfo storage farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][msg.sender];

        require(
            farm.isNft,
            "TokenStand Farming: invalid staking token for this farming pool"
        );

        updateFarm(fid, msg.sender);

        uint256 standReward = 0;

        if (user.amount > 0) {
            standReward = user.amount.mul(farm.accStandPerShare).div(1e12).sub(
                user.rewardDebt
            );
            if (standReward > 0) {
                safeStandTransfer(msg.sender, standReward);
            }
        }

        IERC721(stakingTokens[fid]).safeTransferFrom(
            address(msg.sender),
            address(this),
            tokenId
        );
        user.amount = user.amount.add(1);

        user.rewardDebt = user.amount.mul(farm.accStandPerShare).div(1e12);
        emit StakedSingleNft(msg.sender, fid, tokenId, standReward);
    }

    // Deposit single NFT token to MasterChef for STAND (and Gift) allocation
    function stakeBatchNft(uint256 fid, uint256[] calldata tokenIds)
        external
        nonReentrant
    {
        FarmInfo storage farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][msg.sender];

        require(
            farm.isNft,
            "TokenStand Farming: invalid staking token for this farming pool"
        );

        updateFarm(fid, msg.sender);

        uint256 standReward = 0;
        uint256 amount = tokenIds.length;

        if (user.amount > 0) {
            standReward = user.amount.mul(farm.accStandPerShare).div(1e12).sub(
                user.rewardDebt
            );
            if (standReward > 0) {
                safeStandTransfer(msg.sender, standReward);
            }
        }

        _batchSafeTransferFrom(
            stakingTokens[fid],
            address(msg.sender),
            address(this),
            tokenIds
        );
        user.amount = user.amount.add(amount);

        user.rewardDebt = user.amount.mul(farm.accStandPerShare).div(1e12);
        emit StakedBatchNft(msg.sender, fid, tokenIds, standReward);
    }

    // Withdraw ERC20 LP token from MasterChef
    function withdrawLP(uint256 fid, uint256 amount) external nonReentrant {
        FarmInfo storage farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][msg.sender];
        require(
            user.amount >= amount,
            "TokenStand Farming: amount not enough to withdraw"
        );

        updateFarm(fid, msg.sender);

        uint256 standReward = user
            .amount
            .mul(farm.accStandPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
        uint256 giftReward = user.rewards;
        if (standReward > 0) {
            safeStandTransfer(msg.sender, standReward);
        }
        if (giftReward > 0) {
            user.rewards = 0;
            farm.gift.safeTransfer(msg.sender, giftReward);
        }

        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            IERC20(stakingTokens[fid]).safeTransfer(
                address(msg.sender),
                amount
            );
        }
        user.rewardDebt = user.amount.mul(farm.accStandPerShare).div(1e12);
        emit WithdrawnLP(msg.sender, fid, amount, standReward, giftReward);
    }

    // Withdraw single NFT staked from MasterChef
    function withdrawSingleNft(uint256 fid, uint256 tokenId)
        external
        nonReentrant
    {
        FarmInfo storage farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][msg.sender];

        require(
            farm.isNft,
            "TokenStand Farming: cannot withdraw erc721 token from this farming pool"
        );
        require(
            user.amount >= 1,
            "TokenStand Farming: amount not enough to withdraw"
        );

        updateFarm(fid, msg.sender);

        uint256 standReward = user
            .amount
            .mul(farm.accStandPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
        if (standReward > 0) {
            safeStandTransfer(msg.sender, standReward);
        }

        user.amount = user.amount.sub(1);
        IERC721(stakingTokens[fid]).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
        user.rewardDebt = user.amount.mul(farm.accStandPerShare).div(1e12);
        emit WithdrawnSingleNft(msg.sender, fid, tokenId, standReward);
    }

    // Withdraw batch of NFT tokens from MasterChef
    function withdrawBatchNft(uint256 fid, uint256[] calldata tokenIds)
        external
        nonReentrant
    {
        FarmInfo storage farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][msg.sender];
        uint256 amount = tokenIds.length;

        require(
            farm.isNft,
            "TokenStand Farming: cannot withdraw erc721 token from this farming pool"
        );
        require(
            user.amount >= amount,
            "TokenStand Farming: amount not enough to withdraw"
        );

        updateFarm(fid, msg.sender);

        uint256 standReward = user
            .amount
            .mul(farm.accStandPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
        if (standReward > 0) {
            safeStandTransfer(msg.sender, standReward);
        }

        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            _batchSafeTransferFrom(
                stakingTokens[fid],
                address(this),
                msg.sender,
                tokenIds
            );
        }
        user.rewardDebt = user.amount.mul(farm.accStandPerShare).div(1e12);
        emit WithdrawnBatchNft(msg.sender, fid, tokenIds, standReward);
    }

    // Claim reward in NFT farming pool token from MasterChef
    function claimRewardInNftPool(uint256 fid) external nonReentrant {
        FarmInfo storage farm = farmInfo[fid];
        UserInfo storage user = userInfo[fid][msg.sender];

        require(
            farm.isNft,
            "TokenStand Farming: this function only use for erc721 farming pool"
        );

        updateFarm(fid, msg.sender);

        uint256 standReward = 0;
        uint256 giftReward = 0;

        if (user.amount > 0) {
            standReward = user.amount.mul(farm.accStandPerShare).div(1e12).sub(
                user.rewardDebt
            );
            giftReward = user.rewards;
            if (standReward > 0) {
                safeStandTransfer(msg.sender, standReward);
            }
            if (giftReward > 0) {
                user.rewards = 0;
                farm.gift.safeTransfer(msg.sender, giftReward);
            }
        }

        user.rewardDebt = user.amount.mul(farm.accStandPerShare).div(1e12);
        emit ClaimRewardInNftPool(msg.sender, fid, standReward);
    }

    modifier onlyRewardDistribution(uint256 fid) {
        require(
            msg.sender == farmInfo[fid].rewardDistribution,
            "TokenStand Farming: access denied"
        );
        _;
    }

    function lastTimeRewardApplicable(uint256 fid)
        public
        view
        returns (uint256)
    {
        return Math.min(block.timestamp, farmInfo[fid].periodFinish);
    }

    function rewardPerToken(uint256 fid) public view returns (uint256) {
        FarmInfo storage farm = farmInfo[fid];
        uint256 stakingSupply = farm.isNft
            ? IERC721(stakingTokens[fid]).balanceOf(address(this))
            : IERC20(stakingTokens[fid]).balanceOf(address(this));
        if (stakingSupply == 0) {
            return farm.rewardPerTokenStored;
        }
        return
            farm.rewardPerTokenStored.add(
                lastTimeRewardApplicable(fid)
                    .sub(farm.lastUpdateTime)
                    .mul(farm.rewardRate)
                    .div(stakingSupply)
            );
    }

    function notifyRewardAmount(uint256 fid, uint256 reward)
        public
        onlyRewardDistribution(fid)
    {
        FarmInfo storage farm = farmInfo[fid];

        require(!farm.isNft, "TokenStand Farming: it is erc721 farm!");
        require(
            address(farm.gift) != address(0),
            "TokenStand Farming: it is single farm!"
        );

        updateFarm(fid, address(0));

        uint256 scale = farm.scale;
        require(
            reward < uint256(-1).div(scale),
            "TokenStand Farming: reward overflow"
        );
        uint256 duration = farm.duration;
        uint256 rewardRate;

        if (block.timestamp >= farm.periodFinish) {
            require(
                reward >= duration,
                "TokenStand Farming: reward is too small"
            );
            rewardRate = reward.mul(scale).div(duration);
        } else {
            uint256 remaining = farm.periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(farm.rewardRate).div(scale);
            require(
                reward.add(leftover) >= duration,
                "TokenStand Farming: reward is too small"
            );
            rewardRate = reward.add(leftover).mul(scale).div(duration);
        }

        uint256 balance = farm.gift.balanceOf(address(this));
        require(
            rewardRate <= balance.mul(scale).div(duration),
            "TokenStand Farming: reward is too big"
        );

        farm.rewardRate = rewardRate;
        farm.lastUpdateTime = block.timestamp;
        farm.periodFinish = block.timestamp.add(duration);
        emit RewardAdded(fid, farm.gift, reward);
    }

    function setRewardDistribution(uint256 fid, address rewardDistribution)
        external
        onlyOwner
    {
        FarmInfo storage farm = farmInfo[fid];
        farm.rewardDistribution = rewardDistribution;
        emit RewardDistributionChanged(fid, rewardDistribution);
    }

    function setDuration(uint256 fid, uint256 duration)
        external
        onlyRewardDistribution(fid)
    {
        FarmInfo storage farm = farmInfo[fid];
        require(
            block.timestamp >= farm.periodFinish,
            "TokenStand Farming: not finished yet"
        );
        farm.duration = duration;
        emit DurationUpdated(fid, duration);
    }

    function setScale(uint256 fid, uint256 scale) external onlyOwner {
        require(scale > 0, "TokenStand Farming: scale is too low");
        require(scale <= 1e36, "TokenStand Farming: scale is too high");
        FarmInfo storage farm = farmInfo[fid];
        require(
            farm.periodFinish == 0,
            "TokenStand Farming: can't change scale after start"
        );
        farm.scale = scale;
        emit ScaleUpdated(fid, scale);
    }

    /// @notice Withdraw LP token without caring about STAND and rewards. EMERGENCY ONLY.
    /// @param fid The index of the farm. See `farmInfo`.
    function emergencyWithdrawLP(uint256 fid) external {
        FarmInfo storage farm = farmInfo[fid];
        require(!farm.isNft, "TokenStand Farming: it is not LP farming pool!");
        UserInfo storage user = userInfo[fid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewards = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        IERC20(stakingTokens[fid]).safeTransfer(address(msg.sender), amount);

        emit EmergencyWithdrawLP(msg.sender, fid, amount);
    }

    /// @notice Withdraw LP token without caring about STAND and rewards. EMERGENCY ONLY.
    /// @param fid The index of the farm. See `farmInfo`.
    function emergencyWithdrawNft(uint256 fid, uint256[] calldata tokenIds)
        external
    {
        FarmInfo storage farm = farmInfo[fid];
        require(
            farm.isNft,
            "TokenStand Farming: it is not erc721 farming pool!"
        );
        UserInfo storage user = userInfo[fid][msg.sender];
        uint256 withdrawAmount = tokenIds.length;
        uint256 amount = user.amount;
        user.amount = amount.sub(withdrawAmount);
        user.rewardDebt = 0;
        user.rewards = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        if (withdrawAmount == 1) {
            IERC721(stakingTokens[fid]).safeTransferFrom(
                address(this),
                msg.sender,
                tokenIds[0]
            );
        } else {
            _batchSafeTransferFrom(
                stakingTokens[fid],
                address(this),
                msg.sender,
                tokenIds
            );
        }

        emit EmergencyWithdrawNft(msg.sender, fid, tokenIds);
    }

    /// @notice Transfer TokenStand Ownership. UPGRADE CONTRACT ONLY.
    /// @param newMasterChef The address of next version MasterChef.
    function transferStandOwnership(address newMasterChef) public onlyOwner {
        stand.transferOwnership(newMasterChef);
    }

    // Safe stand transfer function, just in case if rounding error causes farm to not have enough STANDs.
    function safeStandTransfer(address _to, uint256 _amount) internal {
        uint256 standBal = stand.balanceOf(address(this));
        if (_amount > standBal) {
            stand.transfer(_to, standBal);
        } else {
            stand.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function _batchSafeTransferFrom(
        address _token,
        address _from,
        address _recepient,
        uint256[] memory _tokenIds
    ) internal {
        for (uint256 i = 0; i != _tokenIds.length; i++) {
            IERC721(_token).safeTransferFrom(_from, _recepient, _tokenIds[i]);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

import "../../introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
      * @dev Safely transfers `tokenId` token from `from` to `to`.
      *
      * Requirements:
      *
      * - `from` cannot be the zero address.
      * - `to` cannot be the zero address.
      * - `tokenId` token must exist and be owned by `from`.
      * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
      * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
      *
      * Emits a {Transfer} event.
      */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../utils/Context.sol";
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () internal {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
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
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// TokenStand.
contract TokenStand is ERC20("TokenStand", "STAND"), Ownable {
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
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

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

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
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
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
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../../utils/Context.sol";
import "./ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
abstract contract ERC20Burnable is Context, ERC20 {
    using SafeMath for uint256;

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public virtual {
        uint256 decreasedAllowance = allowance(account, _msgSender()).sub(amount, "ERC20: burn amount exceeds allowance");

        _approve(account, _msgSender(), decreasedAllowance);
        _burn(account, amount);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../../utils/Context.sol";
import "./IERC20.sol";
import "../../math/SafeMath.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}

{
  "optimizer": {
    "enabled": true,
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
  "metadata": {
    "useLiteralContent": true
  },
  "libraries": {}
}