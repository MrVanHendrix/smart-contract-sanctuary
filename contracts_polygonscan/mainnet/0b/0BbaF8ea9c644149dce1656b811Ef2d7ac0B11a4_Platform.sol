// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "./interfaces/IPlatform.sol";

contract Platform is Initializable, IPlatform, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint80 public latestOracleRoundId;
    uint32 public latestSnapshotTimestamp;
    uint32 public maxTimeAllowedAfterLatestRound;

    bool private canPurgeLatestSnapshot;
    bool public emergencyWithdrawAllowed;
    bool private purgeSnapshots;

    uint8 public maxAllowedLeverage;
    uint16 public override maxCVIValue;

    uint168 public constant MAX_FEE_PERCENTAGE = 10000;
    uint256 public constant PRECISION_DECIMALS = 1e10;

    uint256 public initialTokenToLPTokenRate;

    IERC20Upgradeable public token;
    ICVIOracle public cviOracle;
    ILiquidation public liquidation;
    IFeesCalculator public feesCalculator;
    IFeesCollector public feesCollector;
    IRewardsCollector public rewards;

    uint256 public lpsLockupPeriod;
    uint256 public override buyersLockupPeriod;

    uint256 public totalPositionUnitsAmount;
    uint256 public totalFundingFeesAmount;
    uint256 public totalLeveragedTokensAmount;

    address public stakingContractAddress;
    
    mapping(uint256 => uint256) public cviSnapshots;

    mapping(address => uint256) public lastDepositTimestamp;
    mapping(address => Position) public override positions;

    mapping(address => bool) public noLockPositionAddresses;
    mapping(address => bool) public noPremiumFeeAllowedAddresses;
    mapping(address => bool) public increaseSharedPoolAllowedAddresses;

    mapping(address => bool) public revertLockedTransfered;

    function initialize(IERC20Upgradeable _token, string memory _lpTokenName, string memory _lpTokenSymbolName, uint256 _initialTokenToLPTokenRate, uint16 _maxCVIValue,
        IFeesCalculator _feesCalculator,
        ICVIOracle _cviOracle,
        ILiquidation _liquidation) public initializer {

        maxTimeAllowedAfterLatestRound = 5 hours;
        canPurgeLatestSnapshot = false;
        emergencyWithdrawAllowed = false;
        purgeSnapshots = true;

        maxAllowedLeverage = 1;

        lpsLockupPeriod = 3 days;
        buyersLockupPeriod = 6 hours;

        stakingContractAddress = address(0);

        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init();
        ERC20Upgradeable.__ERC20_init(_lpTokenName, _lpTokenSymbolName);

        token = _token;
        initialTokenToLPTokenRate = _initialTokenToLPTokenRate;
        maxCVIValue = _maxCVIValue;
        feesCalculator = _feesCalculator;
        cviOracle = _cviOracle;
        liquidation = _liquidation;
    }

    function deposit(uint256 _tokenAmount, uint256 _minLPTokenAmount) external virtual override nonReentrant returns (uint256 lpTokenAmount) {
        return _deposit(_tokenAmount, _minLPTokenAmount);
    }

    function withdraw(uint256 _tokenAmount, uint256 _maxLPTokenBurnAmount) external override nonReentrant returns (uint256 burntAmount, uint256 withdrawnAmount) {
        (burntAmount, withdrawnAmount) = _withdraw(_tokenAmount, false, _maxLPTokenBurnAmount);
    }

    function withdrawLPTokens(uint256 _lpTokensAmount) external override nonReentrant returns (uint256 burntAmount, uint256 withdrawnAmount) {
        require(_lpTokensAmount > 0); // "Amount must be positive"
        (burntAmount, withdrawnAmount) = _withdraw(0, true, _lpTokensAmount);
    }

    function increaseSharedPool(uint256 _tokenAmount) external virtual override nonReentrant {
        _increaseSharedPool(_tokenAmount);
    }

    function openPositionWithoutPremiumFee(uint168 _tokenAmount, uint16 _maxCVI, uint8 _leverage) external override virtual nonReentrant returns (uint168 positionUnitsAmount, uint168 positionedTokenAmount) {
        require(noPremiumFeeAllowedAddresses[msg.sender]); // "Not allowed"
        return _openPosition(_tokenAmount, _maxCVI, feesCalculator.openPositionLPFeePercent(), _leverage, false);
    }

    function openPosition(uint168 _tokenAmount, uint16 _maxCVI, uint16 _maxBuyingPremiumFeePercentage, uint8 _leverage) external override virtual nonReentrant returns (uint168 positionUnitsAmount, uint168 positionedTokenAmount) {
        return _openPosition(_tokenAmount, _maxCVI, _maxBuyingPremiumFeePercentage, _leverage, true);
    }

    function closePosition(uint168 _positionUnitsAmount, uint16 _minCVI) external override nonReentrant returns (uint256 tokenAmount) {
        require(_positionUnitsAmount > 0); // "Position units not positive"
        require(_minCVI > 0 && _minCVI <= maxCVIValue, "Bad min CVI value");

        Position storage position = positions[msg.sender];

        bool isNoLockPositionAddress = noLockPositionAddresses[msg.sender];

        require(position.positionUnitsAmount >= _positionUnitsAmount, "Not enough opened position units");
        require(block.timestamp - position.creationTimestamp >= buyersLockupPeriod  || isNoLockPositionAddress, "Position locked");

        (uint16 cviValue, uint256 latestSnapshot,) = updateSnapshots(true);
        require(cviValue >= _minCVI, "CVI too low");

        (uint256 positionBalance, uint256 fundingFees, uint256 marginDebt, bool wasLiquidated) = _closePosition(position, _positionUnitsAmount, latestSnapshot, cviValue);

        // If was liquidated, balance is negative, nothing to return
        if (wasLiquidated) {
            return 0;
        }

        (uint256 newTotalPositionUnitsAmount, uint256 newTotalFundingFeesAmount) = subtractTotalPositionUnits(_positionUnitsAmount, fundingFees);
        totalPositionUnitsAmount = newTotalPositionUnitsAmount;
        totalFundingFeesAmount = newTotalFundingFeesAmount;
        position.positionUnitsAmount = position.positionUnitsAmount - _positionUnitsAmount;

        uint256 closePositionFee = positionBalance * feesCalculator.calculateClosePositionFeePercent(position.creationTimestamp, isNoLockPositionAddress) / MAX_FEE_PERCENTAGE;

        emit ClosePosition(msg.sender, positionBalance + fundingFees, closePositionFee + fundingFees, position.positionUnitsAmount, position.leverage, cviValue);

        if (position.positionUnitsAmount == 0) {
            delete positions[msg.sender];
        }

        totalLeveragedTokensAmount = totalLeveragedTokensAmount - positionBalance - marginDebt;
        tokenAmount = positionBalance - closePositionFee;

        collectProfit(closePositionFee);
        transferFunds(tokenAmount);
    }

    function _closePosition(Position storage _position, uint256 _positionUnitsAmount, uint256 _latestSnapshot, uint16 _cviValue) private returns (uint256 positionBalance, uint256 fundingFees, uint256 marginDebt, bool wasLiquidated) {
        fundingFees = _calculateFundingFees(cviSnapshots[_position.creationTimestamp], _latestSnapshot, _positionUnitsAmount);
        
        (uint256 currentPositionBalance, bool isPositive, uint256 __marginDebt) = __calculatePositionBalance(_positionUnitsAmount, _position.leverage, _cviValue, _position.openCVIValue, fundingFees);
        
        // Position might be liquidable but balance is positive, we allow to avoid liquidity in such a condition
        if (!isPositive) {
            checkAndLiquidatePosition(msg.sender, false); // Will always liquidate
            wasLiquidated = true;
            fundingFees = 0;
        } else {
            positionBalance = currentPositionBalance;
            marginDebt = __marginDebt;
        }
    }

    function liquidatePositions(address[] calldata _positionOwners) external override nonReentrant returns (uint256 finderFeeAmount) {
        updateSnapshots(true);
        bool liquidationOccured = false;
        for ( uint256 i = 0; i < _positionOwners.length; i++) {
            Position memory position = positions[_positionOwners[i]];

            if (position.positionUnitsAmount > 0) {
                (bool wasLiquidated, uint256 liquidatedAmount, bool isPositive) = checkAndLiquidatePosition(_positionOwners[i], false);

                if (wasLiquidated) {
                    liquidationOccured = true;
                    finderFeeAmount = finderFeeAmount + liquidation.getLiquidationReward(liquidatedAmount, isPositive, position.positionUnitsAmount, position.openCVIValue, position.leverage);
                }
            }
        }

        require(liquidationOccured, "No liquidatable position");

        totalLeveragedTokensAmount = totalLeveragedTokensAmount - finderFeeAmount;
        transferFunds(finderFeeAmount);
    }

    function setSubContracts(IFeesCollector _newCollector, ICVIOracle _newOracle, IRewardsCollector _newRewards, ILiquidation _newLiquidation, address _newStakingContractAddress) external override onlyOwner {
        if (address(feesCollector) != address(0) && address(token) != address(0)) {
            token.safeApprove(address(feesCollector), 0);
        }

        feesCollector = _newCollector;

        if (address(_newCollector) != address(0) && address(token) != address(0)) {
            token.safeApprove(address(_newCollector), type(uint256).max);
        }

        cviOracle = _newOracle;
        rewards = _newRewards;
        liquidation = _newLiquidation;
        stakingContractAddress = _newStakingContractAddress;
    }

    function setFeesCalculator(IFeesCalculator _newCalculator) external override onlyOwner {
        feesCalculator = _newCalculator;
    }

    function setLatestOracleRoundId(uint80 _newOracleRoundId) external override onlyOwner {
        latestOracleRoundId = _newOracleRoundId;
    }

    function setMaxTimeAllowedAfterLatestRound(uint32 _newMaxTimeAllowedAfterLatestRound) external override onlyOwner {
        require(_newMaxTimeAllowedAfterLatestRound >= 1 hours); // "Max time too short"
        maxTimeAllowedAfterLatestRound = _newMaxTimeAllowedAfterLatestRound;
    }

    function setLockupPeriods(uint256 _newLPLockupPeriod, uint256 _newBuyersLockupPeriod) external override onlyOwner {
        require(_newLPLockupPeriod <= 2 weeks); // "Lockup too long"
        lpsLockupPeriod = _newLPLockupPeriod;

        require(_newBuyersLockupPeriod <= 1 weeks); // "Lockup too long"
        buyersLockupPeriod = _newBuyersLockupPeriod;
    }

    function setAddressSpecificParameters(address _holderAddress, bool _shouldLockPosition, bool _noPremiumFeeAllowed, bool _increaseSharedPoolAllowed) external override onlyOwner {
        noLockPositionAddresses[_holderAddress] = !_shouldLockPosition;
        noPremiumFeeAllowedAddresses[_holderAddress] = _noPremiumFeeAllowed;
        increaseSharedPoolAllowedAddresses[_holderAddress] = _increaseSharedPoolAllowed;
    }

    function setRevertLockedTransfers(bool _revertLockedTransfers) external override {
        revertLockedTransfered[msg.sender] = _revertLockedTransfers;   
    }

    function setEmergencyParameters(bool _newEmergencyWithdrawAllowed, bool _newCanPurgeSnapshots) external override onlyOwner {
        emergencyWithdrawAllowed = _newEmergencyWithdrawAllowed;
        purgeSnapshots = _newCanPurgeSnapshots;
    }

    function setMaxAllowedLeverage(uint8 _newMaxAllowedLeverage) external override onlyOwner {
        maxAllowedLeverage = _newMaxAllowedLeverage;
    }

    function calculatePositionBalance(address _positionAddress) external view override returns (uint256 currentPositionBalance, bool isPositive, uint168 positionUnitsAmount, uint8 leverage, uint256 fundingFees, uint256 marginDebt) {
        positionUnitsAmount = positions[_positionAddress].positionUnitsAmount;
        leverage = positions[_positionAddress].leverage;
        require(positionUnitsAmount > 0, "No position for given address");
        (currentPositionBalance, isPositive, fundingFees, marginDebt) = _calculatePositionBalance(_positionAddress, true);
    }

    function calculatePositionPendingFees(address _positionAddress, uint168 _positionUnitsAmount) external view override returns (uint256 pendingFees) {
        Position memory position = positions[_positionAddress];
        pendingFees = _calculateFundingFees(cviSnapshots[position.creationTimestamp], 
            cviSnapshots[latestSnapshotTimestamp], _positionUnitsAmount) + calculateLatestFundingFees(latestSnapshotTimestamp, _positionUnitsAmount);
    }

    function totalBalance() public view override returns (uint256 balance) {
        (uint16 cviValue,,) = cviOracle.getCVILatestRoundData();
        return _totalBalance(cviValue);
    }

    function totalBalanceWithAddendum() external view override returns (uint256 balance) {
        return totalBalance() + calculateLatestFundingFees(latestSnapshotTimestamp, totalPositionUnitsAmount);
    }

    function calculateLatestTurbulenceIndicatorPercent() external view override returns (uint16) {
        (uint16 latestCVIValue, ) = cviOracle.getCVIRoundData(latestOracleRoundId);
        IFeesCalculator.SnapshotUpdate memory updateData = 
            feesCalculator.updateSnapshots(latestSnapshotTimestamp, cviSnapshots[block.timestamp], cviSnapshots[latestSnapshotTimestamp], latestOracleRoundId);
        if (updateData.updatedTurbulenceData) {
            return feesCalculator.calculateTurbulenceIndicatorPercent(updateData.totalTime, updateData.totalRounds, latestCVIValue, updateData.cviValue);
        } else {
            return feesCalculator.turbulenceIndicatorPercent();
        }
    }

    function getLiquidableAddresses(address[] calldata _positionOwners) external view override returns (address[] memory) {
        address[] memory addressesToLiquidate = new address[](_positionOwners.length);

        uint256 liquidationAddressesAmount = 0;
        for (uint256 i = 0; i < _positionOwners.length; i++) {
            (uint256 currentPositionBalance, bool isBalancePositive,, ) = _calculatePositionBalance(_positionOwners[i], true);

            Position memory position = positions[_positionOwners[i]];

            if (position.positionUnitsAmount > 0 && liquidation.isLiquidationCandidate(currentPositionBalance, isBalancePositive, position.positionUnitsAmount, position.openCVIValue, position.leverage)) {
                addressesToLiquidate[liquidationAddressesAmount] = _positionOwners[i];
                liquidationAddressesAmount = liquidationAddressesAmount + 1;
            }
        }

        address[] memory addressesToActuallyLiquidate = new address[](liquidationAddressesAmount);
        for (uint256 i = 0; i < liquidationAddressesAmount; i++) {
            addressesToActuallyLiquidate[i] = addressesToLiquidate[i];
        }

        return addressesToActuallyLiquidate;
    }

    function collectTokens(uint256 _tokenAmount) internal virtual {
        token.safeTransferFrom(msg.sender, address(this), _tokenAmount);
    }

    function _deposit(uint256 _tokenAmount, uint256 _minLPTokenAmount) internal returns (uint256 lpTokenAmount) {
        require(_tokenAmount > 0, "Tokens amount must be positive");
        lastDepositTimestamp[msg.sender] = block.timestamp;

        (uint16 cviValue,, uint256 cviValueTimestamp) = updateSnapshots(true);
        require(cviValueTimestamp + maxTimeAllowedAfterLatestRound >= block.timestamp, "Latest cvi too long ago");

        uint256 depositFee = _tokenAmount * feesCalculator.depositFeePercent() / MAX_FEE_PERCENTAGE;

        uint256 tokenAmountToDeposit = _tokenAmount - depositFee;
        uint256 supply = totalSupply();
        uint256 balance = _totalBalance(cviValue);
    
        if (supply > 0 && balance > 0) {
            lpTokenAmount = tokenAmountToDeposit * supply / balance;
        } else {
            lpTokenAmount = tokenAmountToDeposit * initialTokenToLPTokenRate;
        }

        emit Deposit(msg.sender, _tokenAmount, lpTokenAmount, depositFee);

        require(lpTokenAmount >= _minLPTokenAmount, "Too few LP tokens");
        require(lpTokenAmount > 0, "Too few tokens");

        totalLeveragedTokensAmount = totalLeveragedTokensAmount + tokenAmountToDeposit;

        _mint(msg.sender, lpTokenAmount);
        collectTokens(_tokenAmount);
        collectProfit(depositFee);
    }

    function _withdraw(uint256 _tokenAmount, bool _shouldBurnMax, uint256 _maxLPTokenBurnAmount) internal returns (uint256 burntAmount, uint256 withdrawnAmount) {
        require(lastDepositTimestamp[msg.sender] + lpsLockupPeriod <= block.timestamp, "Funds are locked");

        (uint16 cviValue,,) = updateSnapshots(true);

        if (_shouldBurnMax) {
            burntAmount = _maxLPTokenBurnAmount;
            _tokenAmount = burntAmount * _totalBalance(cviValue) / totalSupply();
        } else {
            require(_tokenAmount > 0, "Tokens amount must be positive");

            // Note: rounding up (ceiling) the to-burn amount to prevent precision loss
            burntAmount = (_tokenAmount * totalSupply() - 1) / _totalBalance(cviValue) + 1;
            require(burntAmount <= _maxLPTokenBurnAmount, "Too much LP tokens to burn");
        }

        require(burntAmount <= balanceOf(msg.sender), "Not enough LP tokens for account");
        require(emergencyWithdrawAllowed || totalLeveragedTokensAmount - totalPositionUnitsAmount >= _tokenAmount, "Collateral ratio broken");

        totalLeveragedTokensAmount = totalLeveragedTokensAmount - _tokenAmount;

        uint256 withdrawFee = _tokenAmount * feesCalculator.withdrawFeePercent() / MAX_FEE_PERCENTAGE;
        withdrawnAmount = _tokenAmount - withdrawFee;

        emit Withdraw(msg.sender, _tokenAmount, burntAmount, withdrawFee);
        
        _burn(msg.sender, burntAmount);

        collectProfit(withdrawFee);
        transferFunds(withdrawnAmount);
    }

    function _increaseSharedPool(uint256 _tokenAmount) internal {
        require(increaseSharedPoolAllowedAddresses[msg.sender]); // "Not allowed"
        totalLeveragedTokensAmount = totalLeveragedTokensAmount + _tokenAmount;
        collectTokens(_tokenAmount);
    }

    struct OpenPositionLocals {
        uint256 totalLeveragedTokensAmount;
        uint256 collateralRatio;
        uint256 latestSnapshot;
        uint256 openPositionFee;
        uint256 maxPositionUnitsAmount;
        uint256 lastCollateralRatio;
        uint256 __positionUnitsAmount;
        uint256 cviValueTimestamp;
        uint168 addedPositionUnitsAmount;
        uint168 buyingPremiumFee;
        uint168 buyingPremiumFeePercentage;
        uint16 cviValue;
        uint16 openPositionFeePercent;
        uint16 buyingPremiumFeeMaxPercent;
    }

    function _openPosition(uint168 _tokenAmount, uint16 _maxCVI, uint168 _maxBuyingPremiumFeePercentage, uint8 _leverage, bool _chargePremiumFee) internal returns (uint168 positionUnitsAmount, uint168 positionedTokenAmount) {
        require(_leverage > 0, "Leverage must be positive");
        require(_leverage <= maxAllowedLeverage, "Leverage excceeds max allowed");
        require(_tokenAmount > 0, "Tokens amount must be positive");
        require(_maxCVI > 0 && _maxCVI <= maxCVIValue, "Bad max CVI value");

        OpenPositionLocals memory locals;

        (locals.cviValue, locals.latestSnapshot, locals.cviValueTimestamp) = updateSnapshots(false);
        require(locals.cviValue <= _maxCVI, "CVI too high");
        require(locals.cviValueTimestamp + maxTimeAllowedAfterLatestRound >= block.timestamp, "Latest cvi too long ago");

        (locals.openPositionFeePercent, locals.buyingPremiumFeeMaxPercent) = feesCalculator.openPositionFees();

        locals.openPositionFee = _tokenAmount * _leverage * locals.openPositionFeePercent / MAX_FEE_PERCENTAGE;

        // Calculate buying premium fee, assuming the maxmimum 

        locals.totalLeveragedTokensAmount = totalLeveragedTokensAmount;

        if (_chargePremiumFee) {
            locals.lastCollateralRatio = totalPositionUnitsAmount * PRECISION_DECIMALS / locals.totalLeveragedTokensAmount;

            locals.maxPositionUnitsAmount = (uint256(_tokenAmount) - locals.openPositionFee) * _leverage * maxCVIValue / locals.cviValue;
            locals.collateralRatio = (totalPositionUnitsAmount + locals.maxPositionUnitsAmount) * PRECISION_DECIMALS / 
                (locals.totalLeveragedTokensAmount + (_tokenAmount - locals.openPositionFee) * _leverage);
            (locals.buyingPremiumFee, locals.buyingPremiumFeePercentage) = feesCalculator.calculateBuyingPremiumFee(_tokenAmount, _leverage, locals.collateralRatio, locals.lastCollateralRatio);

            require(locals.buyingPremiumFeePercentage <= _maxBuyingPremiumFeePercentage, "Premium fee too high");
        } else if (feesCalculator.openPositionLPFeePercent() > 0) {
            locals.buyingPremiumFeePercentage = feesCalculator.openPositionLPFeePercent();
            locals.buyingPremiumFee = _tokenAmount * _leverage * locals.buyingPremiumFeePercentage / MAX_FEE_PERCENTAGE;
        }
        
        // Leaving buying premium in shared pool
        positionedTokenAmount = uint168((_tokenAmount - locals.openPositionFee - locals.buyingPremiumFee) * _leverage);
        
        Position storage position = positions[msg.sender];

        if (position.positionUnitsAmount > 0) {
            require(_leverage == position.leverage); // "Cannot merge different margin"
            MergePositionResults memory mergePositionResults = _mergePosition(position, locals.latestSnapshot, locals.cviValue, positionedTokenAmount, _leverage);
            positionUnitsAmount = mergePositionResults.positionUnitsAmount;
            locals.addedPositionUnitsAmount = mergePositionResults.addedPositionUnitsAmount;
            totalLeveragedTokensAmount = locals.totalLeveragedTokensAmount + positionedTokenAmount + mergePositionResults.positionBalance * _leverage + locals.buyingPremiumFee -
                mergePositionResults.marginDebt - mergePositionResults.positionBalance;
        } else {
            locals.__positionUnitsAmount = uint256(positionedTokenAmount) * maxCVIValue / locals.cviValue;
            positionUnitsAmount = uint168(locals.__positionUnitsAmount);
            require(positionUnitsAmount == locals.__positionUnitsAmount); // "Too much position units"

            locals.addedPositionUnitsAmount = positionUnitsAmount;

            Position memory newPosition = Position(positionUnitsAmount, _leverage, locals.cviValue, uint32(block.timestamp), uint32(block.timestamp));

            positions[msg.sender] = newPosition;
            totalPositionUnitsAmount = totalPositionUnitsAmount + positionUnitsAmount;

            totalLeveragedTokensAmount = locals.totalLeveragedTokensAmount + positionedTokenAmount + locals.buyingPremiumFee;
        }

        emit OpenPosition(msg.sender, _tokenAmount, _leverage, locals.openPositionFee + locals.buyingPremiumFee, positionUnitsAmount, locals.cviValue);

        collectTokens(_tokenAmount);
        collectProfit(locals.openPositionFee);

        require(totalPositionUnitsAmount <= totalLeveragedTokensAmount, "Not enough liquidity");

        if (address(rewards) != address(0) && locals.addedPositionUnitsAmount != 0) {
            rewards.reward(msg.sender, locals.addedPositionUnitsAmount, _leverage);
        }
    }

    struct MergePositionResults {
        uint168 positionUnitsAmount;
        uint168 addedPositionUnitsAmount;
        uint256 marginDebt;
        uint256 positionBalance;
    }

    struct MergePositionLocals {
        uint168 oldPositionUnits;
        uint256 newPositionUnits;
        uint256 newTotalPositionUnitsAmount;
        uint256 newTotalFundingFeesAmount;
    }

    function _mergePosition(Position storage _position, uint256 _latestSnapshot, uint16 _cviValue, uint256 _leveragedTokenAmount, uint8 _leverage) private returns (MergePositionResults memory mergePositionResults) {
        MergePositionLocals memory locals;

        locals.oldPositionUnits = _position.positionUnitsAmount;
        (uint256 currentPositionBalance, uint256 fundingFees, uint256 __marginDebt, bool wasLiquidated) = _closePosition(_position, locals.oldPositionUnits, _latestSnapshot, _cviValue);
        
        // If was liquidated, balance is negative
        if (wasLiquidated) {
            currentPositionBalance = 0;
            locals.oldPositionUnits = 0;
            __marginDebt = 0;
        }

        locals.newPositionUnits = (currentPositionBalance * _leverage + _leveragedTokenAmount) * maxCVIValue / _cviValue;
        mergePositionResults.positionUnitsAmount = uint168(locals.newPositionUnits);
        require(mergePositionResults.positionUnitsAmount == locals.newPositionUnits); // "Too much position units"

        _position.creationTimestamp = uint32(block.timestamp);
        _position.positionUnitsAmount = mergePositionResults.positionUnitsAmount;
        _position.openCVIValue = _cviValue;
        _position.leverage = _leverage;

        (locals.newTotalPositionUnitsAmount, locals.newTotalFundingFeesAmount) = subtractTotalPositionUnits(locals.oldPositionUnits, fundingFees);
        totalFundingFeesAmount = locals.newTotalFundingFeesAmount;
        totalPositionUnitsAmount = locals.newTotalPositionUnitsAmount + mergePositionResults.positionUnitsAmount;
        mergePositionResults.marginDebt = __marginDebt;
        mergePositionResults.positionBalance = currentPositionBalance;

        if (locals.oldPositionUnits < mergePositionResults.positionUnitsAmount) {
            mergePositionResults.addedPositionUnitsAmount = mergePositionResults.positionUnitsAmount - locals.oldPositionUnits;
        }
    }

    function transferFunds(uint256 _tokenAmount) internal virtual {
        token.safeTransfer(msg.sender, _tokenAmount);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        if (from == stakingContractAddress) {
            lastDepositTimestamp[to] = block.timestamp;
        } else if (lastDepositTimestamp[from] + lpsLockupPeriod > block.timestamp && 
            lastDepositTimestamp[from] > lastDepositTimestamp[to] && 
            to != stakingContractAddress) {
                require(!revertLockedTransfered[to], "Recipient refuses locked tokens");
                lastDepositTimestamp[to] = lastDepositTimestamp[from];
        }
    }

    function sendProfit(uint256 _amount, IERC20Upgradeable _token) internal virtual {
        feesCollector.sendProfit(_amount, IERC20(address(_token)));
    }

    function updateSnapshots(bool _canPurgeLatestSnapshot) private returns (uint16 latestCVIValue, uint256 latestSnapshot, uint256 latestCVIValueTimestamp) {
        uint80 originalLatestRoundId = latestOracleRoundId;
        uint256 latestTimestamp = latestSnapshotTimestamp;

        IFeesCalculator.SnapshotUpdate memory updateData = 
            feesCalculator.updateSnapshots(latestTimestamp, cviSnapshots[block.timestamp], cviSnapshots[latestTimestamp], latestOracleRoundId);

        if (updateData.updatedSnapshot) {
            cviSnapshots[block.timestamp] = updateData.latestSnapshot;
            totalFundingFeesAmount = totalFundingFeesAmount + (updateData.singleUnitFundingFee * totalPositionUnitsAmount / PRECISION_DECIMALS);
        }

        if (updateData.updatedLatestRoundId) {
            latestOracleRoundId = updateData.newLatestRoundId;
        }

        if (updateData.updatedTurbulenceData) {
            (latestCVIValue, ) = cviOracle.getCVIRoundData(originalLatestRoundId);
            feesCalculator.updateTurbulenceIndicatorPercent(updateData.totalTime, updateData.totalRounds, latestCVIValue, updateData.cviValue);
        }

        if (updateData.updatedLatestTimestamp) {
            latestSnapshotTimestamp = uint32(block.timestamp);

            // Delete old snapshot if it can be deleted (not an open snapshot) to save gas
            if (canPurgeLatestSnapshot && purgeSnapshots) {
                delete cviSnapshots[latestTimestamp];
            }

            // Update purge since timestamp has changed and it is safe
            canPurgeLatestSnapshot = _canPurgeLatestSnapshot;
        } else if (canPurgeLatestSnapshot) {
            // Update purge only from true to false, so if an open was in the block, will never be purged
            canPurgeLatestSnapshot = _canPurgeLatestSnapshot;
        }

        return (updateData.cviValue, updateData.latestSnapshot, updateData.cviValueTimestamp);
    }

    function _totalBalance(uint16 _cviValue) private view returns (uint256 balance) {
        return totalLeveragedTokensAmount + totalFundingFeesAmount - (totalPositionUnitsAmount * _cviValue) / maxCVIValue;
    }

    function collectProfit(uint256 amount) private {
        if (amount > 0 && address(feesCollector) != address(0)) {
            sendProfit(amount, token);
        }
    }

    function checkAndLiquidatePosition(address _positionAddress, bool _withAddendum) private returns (bool wasLiquidated, uint256 liquidatedAmount, bool isPositive) {
        (uint256 currentPositionBalance, bool isBalancePositive, uint256 fundingFees, uint256 marginDebt) = _calculatePositionBalance(_positionAddress, _withAddendum);
        isPositive = isBalancePositive;
        liquidatedAmount = currentPositionBalance;

        Position memory position = positions[_positionAddress];

        if (liquidation.isLiquidationCandidate(currentPositionBalance, isBalancePositive, position.positionUnitsAmount, position.openCVIValue, position.leverage)) {
            (uint256 newTotalPositionUnitsAmount, uint256 newTotalFundingFeesAmount) = subtractTotalPositionUnits(position.positionUnitsAmount, fundingFees);
            totalPositionUnitsAmount = newTotalPositionUnitsAmount;
            totalFundingFeesAmount = newTotalFundingFeesAmount;
            totalLeveragedTokensAmount = totalLeveragedTokensAmount - marginDebt;

            emit LiquidatePosition(_positionAddress, currentPositionBalance, isBalancePositive, position.positionUnitsAmount);

            delete positions[_positionAddress];
            wasLiquidated = true;
        }
    }

    function subtractTotalPositionUnits(uint168 _positionUnitsAmountToSubtract, uint256 _fundingFeesToSubtract) private view returns (uint256 newTotalPositionUnitsAmount, uint256 newTotalFundingFeesAMount) {
        newTotalPositionUnitsAmount = totalPositionUnitsAmount - _positionUnitsAmountToSubtract;
        newTotalFundingFeesAMount = totalFundingFeesAmount;
        if (newTotalPositionUnitsAmount == 0) {
            newTotalFundingFeesAMount = 0;
        } else {
            newTotalFundingFeesAMount = newTotalFundingFeesAMount - _fundingFeesToSubtract;
        }
    }

    function _calculatePositionBalance(address _positionAddress, bool _withAddendum) private view returns (uint256 currentPositionBalance, bool isPositive, uint256 fundingFees, uint256 marginDebt) {
        Position memory position = positions[_positionAddress];

        (uint16 cviValue,,) = cviOracle.getCVILatestRoundData();

        fundingFees = _calculateFundingFees(cviSnapshots[position.creationTimestamp], cviSnapshots[latestSnapshotTimestamp], position.positionUnitsAmount);
        if (_withAddendum) {
            fundingFees = fundingFees + calculateLatestFundingFees(latestSnapshotTimestamp, position.positionUnitsAmount);
        }
        
        (currentPositionBalance, isPositive, marginDebt) = __calculatePositionBalance(position.positionUnitsAmount, position.leverage, cviValue, position.openCVIValue, fundingFees);
    }

    function __calculatePositionBalance(uint256 _positionUnits, uint8 _leverage, uint16 _cviValue, uint16 _openCVIValue, uint256 _fundingFees) private view returns (uint256 currentPositionBalance, bool isPositive, uint256 marginDebt) {
        uint256 positionBalanceWithoutFees = _positionUnits * _cviValue / maxCVIValue;

        marginDebt = _leverage > 1 ? _positionUnits * _openCVIValue * (_leverage - 1) / maxCVIValue / _leverage : 0;
        uint256 totalDebt = marginDebt + _fundingFees;

        if (positionBalanceWithoutFees >= totalDebt) {
            currentPositionBalance = positionBalanceWithoutFees - totalDebt;
            isPositive = true;
        } else {
            currentPositionBalance = totalDebt - positionBalanceWithoutFees;
        }
    }

    function calculateLatestFundingFees(uint256 startTime, uint256 positionUnitsAmount) private view returns (uint256) {
        IFeesCalculator.SnapshotUpdate memory updateData = 
            feesCalculator.updateSnapshots(latestSnapshotTimestamp, cviSnapshots[block.timestamp], cviSnapshots[latestSnapshotTimestamp], latestOracleRoundId);
        return _calculateFundingFees(cviSnapshots[startTime], updateData.latestSnapshot, positionUnitsAmount);
    }

    function _calculateFundingFees(uint256 startTimeSnapshot, uint256 endTimeSnapshot, uint256 positionUnitsAmount) internal pure returns (uint256) {
        return (endTimeSnapshot - startTimeSnapshot) * positionUnitsAmount / PRECISION_DECIMALS;
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

interface ICVIOracle {
    function getCVIRoundData(uint80 roundId) external view returns (uint16 cviValue, uint256 cviTimestamp);
    function getCVILatestRoundData() external view returns (uint16 cviValue, uint80 cviRoundId, uint256 cviTimestamp);

    function setDeviationCheck(bool newDeviationCheck) external;
    function setMaxDeviation(uint16 newMaxDeviation) external;
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "./ICVIOracle.sol";

interface IFeesCalculator {

    struct CVIValue {
        uint256 period;
        uint16 cviValue;
    }

    struct SnapshotUpdate {
        uint256 latestSnapshot;
        uint256 singleUnitFundingFee;
        uint256 totalTime;
        uint256 totalRounds;
        uint256 cviValueTimestamp;
        uint80 newLatestRoundId;
        uint16 cviValue;
        bool updatedSnapshot;
        bool updatedLatestRoundId;
        bool updatedLatestTimestamp;
        bool updatedTurbulenceData;
    }

    function updateTurbulenceIndicatorPercent(uint256 totalTime, uint256 newRounds, uint16 lastCVIValue, uint16 currCVIValue) external returns (uint16 _updateTurbulenceIndicatorPercent);

    function setOracle(ICVIOracle cviOracle) external;

    function setTurbulenceUpdator(address newUpdator) external;

    function setDepositFee(uint16 newDepositFeePercentage) external;
    function setWithdrawFee(uint16 newWithdrawFeePercentage) external;
    function setOpenPositionFee(uint16 newOpenPositionFeePercentage) external;
    function setOpenPositionLPFee(uint16 newOpenPositionLPFeePercent) external;
    function setClosePositionFee(uint16 newClosePositionFeePercentage) external;
    function setClosePositionMaxFee(uint16 newClosePositionMaxFeePercentage) external;
    function setClosePositionFeeDecay(uint256 newClosePositionFeeDecayPeriod) external;
    
    function setOracleHeartbeatPeriod(uint256 newOracleHeartbeatPeriod) external;
    function setBuyingPremiumFeeMax(uint16 newBuyingPremiumFeeMaxPercentage) external;
    function setBuyingPremiumThreshold(uint16 newBuyingPremiumThreshold) external;
    function setCollateralToBuyingPremiumMapping(uint16[] calldata newCollateralToBuyingPremiumMapping) external;
    function setFundingFeeConstantRate(uint16 newfundingFeeConstantRate) external;
    function setTurbulenceStep(uint16 newTurbulenceStepPercentage) external;
    function setMaxTurbulenceFeePercentToTrim(uint16 newMaxTurbulenceFeePercentToTrim) external;
    function setTurbulenceDeviationThresholdPercent(uint16 newTurbulenceDeviationThresholdPercent) external;
    function setTurbulenceDeviationPercent(uint16 newTurbulenceDeviationPercentage) external;

    function calculateTurbulenceIndicatorPercent(uint256 totalHeartbeats, uint256 newRounds, uint16 _lastCVIValue, uint16 _currCVIValue) external view returns (uint16);

    function calculateBuyingPremiumFee(uint168 tokenAmount, uint8 leverage, uint256 collateralRatio, uint256 lastCollateralRatio) external view returns (uint168 buyingPremiumFee, uint16 combinedPremiumFeePercentage);
    function calculateBuyingPremiumFeeWithTurbulence(uint168 tokenAmount, uint8 leverage, uint256 collateralRatio, uint256 lastCollateralRatio, uint16 _turbulenceIndicatorPercent) external view returns (uint168 buyingPremiumFee, uint16 combinedPremiumFeePercentage);
    
    function calculateSingleUnitFundingFee(CVIValue[] memory cviValues) external view returns (uint256 fundingFee);
    function updateSnapshots(uint256 latestTimestamp, uint256 blockTimestampSnapshot, uint256 latestTimestampSnapshot, uint80 latestOracleRoundId) external view returns (SnapshotUpdate memory snapshotUpdate);

    function calculateClosePositionFeePercent(uint256 creationTimestamp, bool isNoLockPositionAddress) external view returns (uint16);
    function calculateWithdrawFeePercent(uint256 lastDepositTimestamp) external view returns (uint16);

    function depositFeePercent() external view returns (uint16);
    function withdrawFeePercent() external view returns (uint16);
    function openPositionFeePercent() external view returns (uint16);
    function closePositionFeePercent() external view returns (uint16);
    function openPositionLPFeePercent() external view returns (uint16);
    function buyingPremiumFeeMaxPercent() external view returns (uint16);

    function openPositionFees() external view returns (uint16 openPositionFeePercentResult, uint16 buyingPremiumFeeMaxPercentResult);

    function turbulenceIndicatorPercent() external view returns (uint16);
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFeesCollector {
    function sendProfit(uint256 amount, IERC20 token) external;
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

interface ILiquidation {	
	function setMinLiquidationThresholdPercents(uint16[8] calldata newMinThresholdPercents) external;
	function setMinLiquidationRewardPercent(uint16 newMinRewardPercent) external;
	function setMaxLiquidationRewardPercents(uint16[8] calldata newMaxRewardPercents) external;
	function isLiquidationCandidate(uint256 positionBalance, bool isPositive, uint168 positionUnitsAmount, uint16 openCVIValue, uint8 leverage) external view returns (bool);
	function getLiquidationReward(uint256 positionBalance, bool isPositive, uint168 positionUnitsAmount, uint16 openCVIValue, uint8 leverage) external view returns (uint256 finderFeeAmount);
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "./ICVIOracle.sol";
import "./IFeesCalculator.sol";
import "./IRewardsCollector.sol";
import "./IFeesCollector.sol";
import "./ILiquidation.sol";

interface IPlatform {

    struct Position {
        uint168 positionUnitsAmount;
        uint8 leverage;
        uint16 openCVIValue;
        uint32 creationTimestamp;
        uint32 originalCreationTimestamp;
    }

    event Deposit(address indexed account, uint256 tokenAmount, uint256 lpTokensAmount, uint256 feeAmount);
    event Withdraw(address indexed account, uint256 tokenAmount, uint256 lpTokensAmount, uint256 feeAmount);
    event OpenPosition(address indexed account, uint256 tokenAmount, uint8 leverage, uint256 feeAmount, uint256 positionUnitsAmount, uint256 cviValue);
    event ClosePosition(address indexed account, uint256 tokenAmount, uint256 feeAmount, uint256 positionUnitsAmount, uint8 leverage, uint256 cviValue);
    event LiquidatePosition(address indexed positionAddress, uint256 currentPositionBalance, bool isBalancePositive, uint256 positionUnitsAmount);

    function deposit(uint256 tokenAmount, uint256 minLPTokenAmount) external returns (uint256 lpTokenAmount);
    function withdraw(uint256 tokenAmount, uint256 maxLPTokenBurnAmount) external returns (uint256 burntAmount, uint256 withdrawnAmount);
    function withdrawLPTokens(uint256 lpTokenAmount) external returns (uint256 burntAmount, uint256 withdrawnAmount);

    function increaseSharedPool(uint256 tokenAmount) external;

    function openPositionWithoutPremiumFee(uint168 tokenAmount, uint16 maxCVI, uint8 leverage) external returns (uint168 positionUnitsAmount, uint168 positionedTokenAmount);
    function openPosition(uint168 tokenAmount, uint16 maxCVI, uint16 maxBuyingPremiumFeePercentage, uint8 leverage) external returns (uint168 positionUnitsAmount, uint168 positionedTokenAmount);
    function closePosition(uint168 positionUnitsAmount, uint16 minCVI) external returns (uint256 tokenAmount);

    function liquidatePositions(address[] calldata positionOwners) external returns (uint256 finderFeeAmount);
    function getLiquidableAddresses(address[] calldata positionOwners) external view returns (address[] memory);

    function setAddressSpecificParameters(address holderAddress, bool shouldLockPosition, bool noPremiumFeeAllowed, bool increaseSharedPoolAllowed) external;

    function setRevertLockedTransfers(bool revertLockedTransfers) external;

    function setSubContracts(IFeesCollector newCollector, ICVIOracle newOracle, IRewardsCollector newRewards, ILiquidation newLiquidation, address _newStakingContractAddress) external;
    function setFeesCalculator(IFeesCalculator newCalculator) external;

    function setLatestOracleRoundId(uint80 newOracleRoundId) external;
    function setMaxTimeAllowedAfterLatestRound(uint32 newMaxTimeAllowedAfterLatestRound) external;

    function setLockupPeriods(uint256 newLPLockupPeriod, uint256 newBuyersLockupPeriod) external;

    function setEmergencyParameters(bool newEmergencyWithdrawAllowed, bool newCanPurgeSnapshots) external;

    function setMaxAllowedLeverage(uint8 newMaxAllowedLeverage) external;

    function calculatePositionBalance(address positionAddress) external view returns (uint256 currentPositionBalance, bool isPositive, uint168 positionUnitsAmount, uint8 leverage, uint256 fundingFees, uint256 marginDebt);
    function calculatePositionPendingFees(address positionAddress, uint168 positionUnitsAmount) external view returns (uint256 pendingFees);

    function totalBalance() external view returns (uint256 balance);
    function totalBalanceWithAddendum() external view returns (uint256 balance);

    function calculateLatestTurbulenceIndicatorPercent() external view returns (uint16);

    function positions(address positionAddress) external view returns (uint168 positionUnitsAmount, uint8 leverage, uint16 openCVIValue, uint32 creationTimestamp, uint32 originalCreationTimestamp);
    function buyersLockupPeriod() external view returns (uint256);
    function maxCVIValue() external view returns (uint16);
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

interface IRewardsCollector {
	function reward(address account, uint256 positionUnits, uint8 leverage) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";
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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {

    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ReentrancyGuardUpgradeable is Initializable {
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

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./extensions/IERC20MetadataUpgradeable.sol";
import "../../utils/ContextUpgradeable.sol";
import "../../proxy/utils/Initializable.sol";

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
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The defaut value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal initializer {
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal initializer {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
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

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
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
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

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

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

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

        _totalSupply += amount;
        _balances[account] += amount;
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

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

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
    uint256[45] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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

pragma solidity ^0.8.0;

import "../IERC20Upgradeable.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20Upgradeable.sol";
import "../../../utils/AddressUpgradeable.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20Upgradeable token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
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

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 100
  },
  "evmVersion": "istanbul",
  "libraries": {},
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  }
}