// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


library Roles {
    bytes32 constant ROLE_ADMIN = keccak256('operator.dabot.role');
    bytes32 constant ROLE_OPERATORS = keccak256('operator.dabot.role');
    bytes32 constant ROLE_TEMPLATE_CREATOR = keccak256('creator.template.dabot.role');
    bytes32 constant ROLE_BOT_CREATOR = keccak256('creator.dabot.role');
}

library AddressBook {
    bytes32 constant ADDR_FACTORY = keccak256('factory.address');
    bytes32 constant ADDR_VICS = keccak256('vics.address');
    bytes32 constant ADDR_TAX = keccak256('tax.address');
    bytes32 constant ADDR_VOTER = keccak256('voter.address');
    bytes32 constant ADDR_BOT_MANAGER = keccak256('botmanager.address');
    bytes32 constant ADDR_VICS_EXCHANGE = keccak256('exchange.vics.address');
}

library Config {
    bytes32 constant PROPOSAL_DEPOSIT = keccak256('deposit.proposal.config');
    bytes32 constant PROPOSAL_REWARD_PERCENT = keccak256('reward.proposal.config');
    bytes32 constant CREATOR_DEPOSIT = keccak256('deposit.creator.config');
}

interface IConfigurator {
    function addressOf(bytes32 addrId) external view returns(address);
    function configOf(bytes32 configId) external view returns(uint);
    function bytesConfigOf(bytes32 configId) external view returns(bytes memory);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IInitializable {
    function init(bytes calldata data) external payable;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRoboFiFactory {
    function deploy(address masterContract, 
                    bytes calldata data, 
                    bool useCreate2) 
        external 
        payable 
        returns(address);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";


string constant ERR_PERMISSION_DENIED = "DABot: permission denied";

bytes32 constant BOT_MODULE_VOTE_CONTROLER = keccak256("vote.dabot.module");
bytes32 constant BOT_MODULE_STAKING_CONTROLER = keccak256("staking.dabot.module");
bytes32 constant BOT_MODULE_CERTIFICATE_TOKEN = keccak256("certificate-token.dabot.module");
bytes32 constant BOT_MODULE_GOVERNANCE_TOKEN = keccak256("governance-token.dabot.module");

bytes32 constant BOT_MODULE_WARMUP_LOCKER = keccak256("warmup.dabot.module");
bytes32 constant BOT_MODULE_COOLDOWN_LOCKER = keccak256("cooldown.dabot.module");

enum BotStatus { PRE_IBO, IN_IBO, ACTIVE, ABANDONED }

struct BotModuleInitData {
    bytes32 moduleId;
    bytes data;
}

struct BotSetting {             // for saving storage, the meta-fields of a bot are encoded into a single uint256 byte slot.
    uint64 iboTime;             // 32 bit low: iboStartTime (unix timestamp), 
                                // 32 bit high: iboEndTime (unix timestamp)
    uint24 stakingTime;         // 8 bit low: warm-up time, 
                                // 8 bit mid: cool-down time
                                // 8 bit high: time unit (0 - day, 1 - hour, 2 - minute, 3 - second)
    uint32 pricePolicy;         // 16 bit low: price multiplier (fixed point, 2 digits for decimal)
                                // 16 bit high: commission fee in percentage (fixed point, 2 digit for decimal)
    uint128 profitSharing;      // packed of 16bit profit sharing: bot-creator, gov-user, stake-user, and robofi-game
    uint initDeposit;           // the intial deposit (in VICS) of bot-creator
    uint initFounderShare;      // the intial shares (i.e., governance token) distributed to bot-creator
    uint maxShare;              // max cap of gtoken supply
    uint iboShare;              // max supply of gtoken for IBO. Constraint: maxShare >= iboShare + initFounderShare
}

struct BotMetaData {
    string name;
    string symbol;
    string version;
    uint8 botType;
    bool abandoned;
    bool isTemplate;        // determine this module is a template, not a bot instance
    bool initialized;       // determines whether the bot has been initialized 
    address botOwner;       // the public address of the bot owner
    address botManager;
    address botTemplate;    // address of the template contract 
    address gToken;         // address of the governance token
}

struct BotDetail { // represents a detail information of a bot, merely use for bot infomation query
    uint id;                    // the unique id of a bot within its manager.
                                // note: this id only has value when calling {DABotManager.queryBots}
    address botAddress;         // the contract address of the bot.

    BotStatus status;           // 0 - PreIBO, 1 - InIBO, 2 - Active, 3 - Abandonned
    uint8 botType;              // type of the bot (inherits from the bot's template)
    string botSymbol;           // get the bot name.
    string botName;             // get the bot full name.
    address governToken;        // the address of the governance token
    address template;           // the address of the master contract which defines the behaviors of this bot.
    string templateName;        // the template name.
    string templateVersion;     // the template version.
    uint iboStartTime;          // the time when IBO starts (unix second timestamp)
    uint iboEndTime;            // the time when IBO ends (unix second timestamp)
    uint warmup;                // the duration (in days) for which the staking profit starts counting
    uint cooldown;              // the duration (in days) for which users could claim back their stake after submiting the redeem request.
    uint priceMul;              // the price multiplier to calculate the price per gtoken (based on the IBO price).
    uint commissionFee;         // the commission fee when buying gtoken after IBO time.
    uint initDeposit;           
    uint initFounderShare;
    uint144 profitSharing;
    uint maxShare;              // max supply of governance token.
    uint circulatedShare;       // the current supply of governance token.
    uint iboShare;              // the max supply of gtoken for IBO.
    uint userShare;             // the amount of governance token in the caller's balance.
    UserPortfolioAsset[] portfolio;
}

struct BotModuleInfo {
    string name;
    string version;
    address handler;
}

struct PortfolioCreationData {
    address asset;
    uint256 cap;            // the maximum stake amount for this asset (bot-lifetime).
    uint256 iboCap;         // the maximum stake amount for this asset within the IBO.
    uint256 weight;         // preference weight for this asset. Use to calculate the max purchasable amount of governance tokens.
}

struct PortfolioAsset {
    address certToken;    // the certificate asset to return to stake-users
    uint256 cap;            // the maximum stake amount for this asset (bot-lifetime).
    uint256 iboCap;         // the maximum stake amount for this asset within the IBO.
    uint256 weight;         // preference weight for this asset. Use to calculate the max purchasable amount of governance tokens.
}

struct UserPortfolioAsset {
    address asset;
    PortfolioAsset info;
    uint256 userStake;
    uint256 totalStake;     // the total stake of all users.
}

/**
@dev Records warming-up certificate tokens of a DABot.
*/
struct LockerData {         
    address bot;            // the DABOT which creates this locker.
    address owner;          // the locker owner, who is albe to unlock and get tokens after the specified release time.
    address token;          // the contract of the certificate token.
    uint64 created_at;      // the moment when locker is created.
    uint64 release_at;      // the monent when locker could be unlock. 
}

/**
@dev Provides detail information of a warming-up token lock, plus extra information.
    */
struct LockerInfo {
    address locker;
    LockerData info;
    uint256 amount;         // the locked amount of cert token within this locker.
    uint256 reward;         // the accumulated rewards
    address asset;          // the stake asset beyond the certificated token
}

struct MintableShareDetail {
    address asset;
    uint stakeAmount;
    uint mintableShare;
    uint weight;
    uint iboCap;
}

struct StakingPNL {
    address asset;
    uint compound;
    uint reward;
    uint compoundMode;  // 0 - increase, 1 - decrrease
}

struct StakingReward {
    address asset;
    uint amount;
}

struct BenefitciaryInfo {
    address account;
    string name;
    string shortName;
    uint weight;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../../common/IInitializable.sol";
import "../interfaces/IDABot.sol";
import "../interfaces/IDABotController.sol";
import "../interfaces/IDABotModule.sol";
import "../interfaces/IDABotGovernToken.sol";
import "../setting/DABotSettingLib.sol";
import "../staking/DABotStakingLib.sol";
import "./DABotControllerLib.sol";

contract DABotModuleController is IInitializable, Context, IDABotControllerEvent {

    using DABotTemplateControllerLib for BotTemplateController;
    using DABotMetaLib for BotMetaData;
    using DABotStakingLib for BotStakingData;
    using DABotSettingLib for BotSetting;

    constructor(string memory name, string memory version) {
        BotMetaData storage ds = DABotMetaLib.metadata();
        ds.name = name;
        ds.version = version;
        ds.botOwner = _msgSender();
        ds.isTemplate = true;
        ds.initialized = true;
    }

    modifier onlyTemplate() {
        require(DABotMetaLib.metadata().isTemplate, "Controller: must call on template"); 
        _;
    }

    modifier onlyOwner() {
        BotMetaData storage ds = DABotMetaLib.metadata();
        require(_msgSender() == ds.botOwner, "Bot: caller is not the owner");
        _;
    }

    function registerModule(address moduleHandler) public onlyTemplate onlyOwner {
        IDABotModule _module = IDABotModule(moduleHandler);
        (string memory _name, string memory _version, bytes32 _moduleId) = _module.moduleInfo();

        BotTemplateController storage ds = DABotTemplateControllerLib.controller();
        bool moduleExisted = ds.moduleAddresses[_moduleId] != address(0);

        (bool success, bytes memory result) = 
            moduleHandler.delegatecall(abi.encodeWithSelector(IDABotModule.onRegister.selector, moduleHandler));
        
        require(success, string(abi.encodePacked("Controller: module ", _name, ' registration error: ',  result)));

        if (!moduleExisted) 
            ds.modules.push(_moduleId);
        
        emit ModuleRegistered(_moduleId, moduleHandler, _name, _version);
    }

    function updateModuleHandler(bytes32 moduleId, address newModuleAddress) public onlyTemplate onlyOwner {
        BotTemplateController storage ds = DABotTemplateControllerLib.controller();
        address oldModuleAddress = ds.registerModule(moduleId, newModuleAddress); 
        emit ModuleHandlerChanged(moduleId, oldModuleAddress, newModuleAddress);
    }

    function module(bytes32 moduleId) external view onlyTemplate returns(address) {
        BotTemplateController storage ds = DABotTemplateControllerLib.controller();
        return ds.module(moduleId);
    }

    function moduleOfSelector(bytes4 selector) public view onlyTemplate returns(address) {
        BotTemplateController storage ds = DABotTemplateControllerLib.controller();
        return ds.moduleOfSelector(selector);
    }

    function init(bytes calldata data) external payable override {
        BotMetaData storage ds = DABotMetaLib.metadata();
        require(!ds.initialized, "Controller: contract initialized");
       
        (BotMetaData memory meta, BotModuleInitData[] memory initData) = 
            abi.decode(data, (BotMetaData, BotModuleInitData[]));

        BotMetaData memory templateMeta = IDABot(meta.botTemplate).metadata();

        ds.name = meta.name;
        ds.symbol = meta.symbol;
        ds.version = meta.version;
        ds.botType = templateMeta.botType;
        ds.botOwner = meta.botOwner;
        ds.botManager = meta.botManager;
        ds.botTemplate = meta.botTemplate;
                
        for(uint i = 0; i < initData.length; i++) {
            address moduleAddress = ds.module(initData[i].moduleId);
            if (moduleAddress == address(0))
                revert(string(abi.encodePacked("Controller: module #", i, "(", Strings.toHexString(uint256(initData[i].moduleId), 32) ,") not found"))); 

            (bool success, bytes memory result) = moduleAddress.delegatecall(abi.encodeWithSelector(IDABotModule.onInitialize.selector, initData[i].data));
            if (!success) {
                revert(string(abi.encodePacked(string(result), ' (module ', Strings.toHexString(uint160(moduleAddress), 20), ")")));
            }
        }
        ds.initialized = true;
    }

    fallback() external payable {
        __forwardCall();
    }

    function __findImplementation() internal view returns(address) {
        BotMetaData storage meta = DABotMetaLib.metadata();
        address moduleAddress;
        if (meta.botTemplate == address(0)) {
            moduleAddress = moduleOfSelector(msg.sig);
        } else {
            moduleAddress = DABotModuleController(payable(meta.botTemplate)).moduleOfSelector(msg.sig);
        }
        if (moduleAddress == address(0)) {
            revert(string(abi.encodePacked("Controller: module handler not found for sig ", Strings.toHexString(uint32(msg.sig), 4)))); 
        }
        return moduleAddress;
    }

    function __forwardCall() internal {
        address handler = __findImplementation();
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), handler, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
                case 0 {
                    revert(0, returndatasize())
                }
                default {
                    return(0, returndatasize())
                }
        }
    }

    receive() external payable {}

    function emergencyWithdraw(address token) external payable onlyOwner {
        if (token == address(0))
            payable(owner()).transfer(address(this).balance);
        else {
            IRoboFiERC20 erc20 = IRoboFiERC20(token);
            erc20.transfer(owner(), erc20.balanceOf(address(this)));
        }
    }

    function qualifiedName() external view returns(string memory) {
        BotMetaData storage meta = DABotMetaLib.coredata().metadata;
        if (meta.isTemplate)
            return string(abi.encodePacked(meta.name,":",meta.version));
        return string(abi.encodePacked(meta.symbol,":",meta.name));
    }

    function metadata() external view returns(BotMetaData memory) {
        return DABotMetaLib.coredata().metadata;
    }

    function governToken() external view returns(IDABotGovernToken) {
        return IDABotGovernToken(DABotMetaLib.metadata().gToken);
    }

    function setting() external view returns(BotSetting memory) {
        return DABotSettingLib.setting();
    }

    function botDetails() external view returns(BotDetail memory output) {
        BotMetaData storage meta = DABotMetaLib.metadata();
        BotStakingData storage staking = DABotStakingLib.staking();
        BotSetting storage _setting = DABotSettingLib.setting();

        BotMetaData memory templateMeta = DABotModuleController(payable(meta.botTemplate)).metadata();
        IDABotGovernToken gToken = IDABotGovernToken(meta.gToken);

        output.botAddress = address(this);
        output.template = meta.botTemplate;
        output.botSymbol = meta.symbol;
        output.botName = meta.name;
        output.status = _setting.status();
        output.botType = templateMeta.botType;
        output.governToken = meta.gToken;
        output.templateName = templateMeta.name; 
        output.templateVersion = templateMeta.version;
        output.iboStartTime = _setting.iboStartTime();
        output.iboEndTime = _setting.iboEndTime();
        output.warmup = _setting.warmupTime();
        output.cooldown = _setting.cooldownTime();
        output.priceMul = _setting.priceMultiplier();
        output.commissionFee = _setting.commission();
        output.profitSharing = _setting.profitSharing;
        output.initDeposit = _setting.initDeposit;
        output.initFounderShare = _setting.initFounderShare;
        output.maxShare = _setting.maxShare;
        output.iboShare = _setting.iboShare;
        output.circulatedShare = gToken.totalSupply();
        output.userShare = gToken.balanceOf(_msgSender());
        output.portfolio = staking.portfolioDetails();
    }

    function owner() public view returns(address) {
        return DABotMetaLib.metadata().botOwner;
    }

    function renounceOwnership() external onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Bot: new owner is zero");
        _transferOwnership(newOwner);
    }

    function abandon(bool value) external onlyOwner {
        DABotMetaLib.metadata().abandoned = value;
        emit BotAbandoned(value);
    }

    function modulesInfo() external view returns(BotModuleInfo[] memory result) {
        BotTemplateController storage ds = DABotTemplateControllerLib.controller();
        result = new BotModuleInfo[](ds.modules.length);
        for (uint i = 0; i < ds.modules.length; i++) {
            IDABotModule moduleHandler = IDABotModule(ds.moduleAddresses[ds.modules[i]]);
            (string memory _name, string memory _version,) = moduleHandler.moduleInfo();
            result[i] = BotModuleInfo(_name, _version, ds.moduleAddresses[ds.modules[i]]);
        }
    }

    function moduleHandlerInfo(bytes32[] calldata ids) external view returns(address[] memory result) {
        BotTemplateController storage ds = DABotTemplateControllerLib.controller();
        result = new address[](ids.length);
        for (uint i = 0; i < ids.length; i++)
            result[i] = ds.moduleAddresses[ids[i]];
    }

    function _transferOwnership(address newOwner) internal {
        BotMetaData storage ds = DABotMetaLib.metadata();
        address oldOwner = ds.botOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
        ds.botOwner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../interfaces/IBotTemplateController.sol";
import "../interfaces/IDABotGovernToken.sol";
import "../interfaces/IDABotManager.sol";
import "../DABotCommon.sol";

struct BotTemplateController {
    mapping(bytes4 => bytes32) selectors;
    mapping(bytes32 => address) moduleAddresses;
    bytes32[] modules;
}

string constant ERR_ADMIN_REQUIRED = "Controller: admin required";  
string constant ERR_CONTRACT_INITIALIZED = "Controller: contract initialized";
string constant ERR_MODULE_EXISTS = "Controller: module exists";
string constant ERR_CERT_TOKEN_NOT_SET = "Controller: certificate token contract is not set";
string constant ERR_GOVERN_TOKEN_NOT_SET = "Controller: governance token contract is not set";
string constant ERR_GOVERN_TOKEN_NOT_DEPLOYED = "Controller: governance token is not deployed";
string constant ERR_WARMUP_LOCKER_NOT_SET = "Controller: warmup locker is not set";
string constant ERR_COOLDOWN_LOCKER_NOT_SET = "Controller: cooldown locker is not set";
string constant ERR_UNKNOWN_MODULE_ID = "Controller: unknown module id";
string constant ERR_BOT_MANAGER_NOT_SET = "Controller: bot manager is not set";
string constant ERR_FACTORY_NOT_SET = "Controller: factory is not set";

struct BotCoreData {
    BotTemplateController controller;
    BotMetaData metadata;
    BotSetting setting;
}

library DABotTemplateControllerLib {

    using DABotTemplateControllerLib for BotTemplateController;

    bytes32 constant CORE_STORAGE_POSITION = keccak256("core.dabot.storage");

    function coredata() internal pure returns(BotCoreData storage ds) {
        bytes32 position = CORE_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function controller() internal view returns (BotTemplateController storage) {
        return coredata().controller;
    }

    function requireNewModule(bytes32 moduleId) internal view {
        BotTemplateController storage ds = controller();
        require(ds.module(moduleId) == address(0), ERR_MODULE_EXISTS);
    }

    function module(BotTemplateController storage ds, bytes32 moduleId) internal view returns(address) {
        return ds.moduleAddresses[moduleId];
    }

    function moduleOfSelector(BotTemplateController storage ds, bytes4 selector) internal view returns(address) {
        bytes32 moduleId = ds.selectors[selector];
        return ds.moduleAddresses[moduleId];
    }

    function registerModule(BotTemplateController storage ds, bytes32 moduleId, address moduleAddress) internal returns(address oldModuleAddress) {
        oldModuleAddress = ds.moduleAddresses[moduleId];
        ds.moduleAddresses[moduleId] = moduleAddress;
    }

    function registerSelectors(BotTemplateController storage ds, bytes32 moduleId, bytes4[] memory selectors) internal {
        for(uint i = 0; i < selectors.length; i++)
            ds.selectors[selectors[i]] = moduleId;
    }

    
}

library DABotMetaLib {

    using DABotMetaLib for BotMetaData;
    using DABotTemplateControllerLib for BotTemplateController;

    bytes32 constant CORE_STORAGE_POSITION = keccak256("core.dabot.storage");

    function coredata() internal pure returns(BotCoreData storage ds) {
        bytes32 position = CORE_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function metadata() internal view returns (BotMetaData storage) {
        return coredata().metadata;
    }

    function manager(BotMetaData storage ds) internal view returns(IDABotManager _manager) {
        _manager = IDABotManager(ds.botManager);
        require(address(_manager) != address(0), ERR_BOT_MANAGER_NOT_SET);
    }

    function configurator(BotMetaData storage ds) internal view returns(IConfigurator _config) {
        _config = ds.manager().configurator();
    }

    function factory(BotMetaData storage ds) internal view returns(IRoboFiFactory _factory) {
        IConfigurator config = ds.configurator();
        _factory = IRoboFiFactory(config.addressOf(AddressBook.ADDR_FACTORY));
        require(address(_factory) != address(0), ERR_FACTORY_NOT_SET);
    }

    function governToken(BotMetaData storage ds) internal view returns(IDABotGovernToken) {
        address gToken = ds.gToken;
        require(gToken != address(0), ERR_GOVERN_TOKEN_NOT_DEPLOYED);
        return IDABotGovernToken(gToken);
    }

    function module(BotMetaData storage ds, bytes32 moduleId) internal view returns(address) {
        if (ds.botTemplate == address(0)) {
            return DABotTemplateControllerLib.controller().module(moduleId);
        }
        return IBotTemplateController(ds.botTemplate).module(moduleId);
    }

    function deployCertToken(BotMetaData storage ds, address asset) internal returns(address) {
        address certTokenMaster = ds.module(BOT_MODULE_CERTIFICATE_TOKEN);
        if (certTokenMaster == address(0)) {
            revert(string(abi.encodePacked(
                ERR_CERT_TOKEN_NOT_SET, 
                '. template: ', 
                Strings.toHexString(uint160(ds.botTemplate), 20)
                )));
        }
        require(certTokenMaster != address(0), ERR_CERT_TOKEN_NOT_SET);

        return ds.factory().deploy(
            certTokenMaster,
            abi.encode(address(this), asset),
            false
        );
    }

    function deployGovernanceToken(BotMetaData storage ds) internal returns(address) {
        address governTokenMaster = ds.module(BOT_MODULE_GOVERNANCE_TOKEN);
        require(governTokenMaster != address(0), ERR_GOVERN_TOKEN_NOT_SET);

        return ds.factory().deploy(
            governTokenMaster,
            abi.encode(address(this)),
            false
        );
    }

    function deployLocker(BotMetaData storage ds, bytes32 lockerType, LockerData memory data) internal returns(address) {
        address lockerMaster = ds.module(lockerType);
        if (lockerMaster == address(0)) {
            if (lockerType == BOT_MODULE_WARMUP_LOCKER)
                revert(ERR_WARMUP_LOCKER_NOT_SET);
            if (lockerType == BOT_MODULE_COOLDOWN_LOCKER) 
                revert(ERR_COOLDOWN_LOCKER_NOT_SET);
            revert(ERR_UNKNOWN_MODULE_ID);
        }
        return ds.factory().deploy(
            lockerMaster,
            abi.encode(data),
            false
        );
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../DABotCommon.sol"; 
import "../interfaces/IBotBenefitciary.sol"; 

struct FundManagementData {
    address[] benefitciaries;
}

address constant BOT_CREATOR_BENEFITCIARY = address(1);
address constant GOV_USER_BENEFITCIARY = address(2);
address constant STAKE_USER_BENEFITCIARY = address(3);

library DABotFundManagerLib {
    bytes32 constant FUND_MANAGER_STORAGE_POSITION = keccak256("fundmanager.dabot.storage");


    function fundData() internal pure returns(FundManagementData storage ds) {
        bytes32 position = FUND_MANAGER_STORAGE_POSITION;
        assembly {
            ds.slot :=  position
        }
    }

    function benefitciaryName(address benefitciary) internal view returns(string memory) {
        if (benefitciary == BOT_CREATOR_BENEFITCIARY)
            return "Bot Creator";
        if (benefitciary == GOV_USER_BENEFITCIARY)
            return "Governance Users";
        if (benefitciary == STAKE_USER_BENEFITCIARY)
            return "Stake Users";
        return IBotBenefitciary(benefitciary).name();
    }

    function benefitciaryShortName(address benefitciary) internal view returns(string memory) {
        if (benefitciary == BOT_CREATOR_BENEFITCIARY)
            return "Bot Creator";
        if (benefitciary == GOV_USER_BENEFITCIARY)
            return "Gov. Users";
        if (benefitciary == STAKE_USER_BENEFITCIARY)
            return "Stake Users";
        return IBotBenefitciary(benefitciary).shortName();
    }

    function addBenefitciary(FundManagementData storage ds, address benefitciary) internal {
        ds.benefitciaries.push(benefitciary);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../DABotCommon.sol"; 


/**
@dev The interface of a bot benefitciary who is awarded from the bot's activities.
 */
interface IBotBenefitciary {

    function name() external view returns(string memory);
    function shortName() external view returns(string memory);
    function onAward(uint amount) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface IBotTemplateController {
    function module(bytes32 moduleId) external view returns(address);
    function moduleOfSelector(bytes32 selector) external view returns(address);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../token/IRoboFiERC20.sol";

struct VaultData {
    address botToken;
    IERC20 asset;
    address bot;
    uint8 index;
    bytes4 vaultType;
}

struct UserInfo {
    uint deposit;
    uint debtPoints;
    uint debt;
    uint lockPeriod;
    uint lastDepositDate;
}

struct VaultInfo {
    VaultData data;
    uint totalDeposit;
    bytes option;
} 

interface IBotVaultEvent {
    event Deposit(uint vID, address indexed payor, address indexed account, uint amount);
    event Widthdraw(uint vID, address indexed account, uint amount);
    event RewardAdded(uint vID, uint assetAmount);
}

interface IBotVault is IBotVaultEvent {
    function deposit(uint vID, uint amount) external;
    function delegateDeposit(uint vID, address payor, address account, uint amount, uint lockTime) external;
    function withdraw(uint vID, uint amount) external;
    function delegateWidthdraw(uint vID, address account, uint amount) external;
    function pendingReward(uint vID, address account) external view returns(uint);
    function balanceOf(uint vID, address account) external view returns(uint);
    function updateReward(uint vID, uint assetAmount) external;

    function getUserInfo(uint vID, address account) external view returns(UserInfo memory result);
    function getVaultInfo(uint vID) external view returns(VaultInfo memory);
    function getVaultOption(uint vID) external view returns(bytes memory);
    function setVaultOption(uint vID, bytes calldata option) external;
}

interface IBotVaultManagerEvent is IBotVaultEvent {
    event OpenVault(uint vID, VaultData data);
    event DestroyVault(uint vID);
    event RegisterHandler(bytes4 vaultType, address handler);
    event BotManagerUpdated(address indexed botManager);
}

interface IBotVaultManager is IBotVault, IBotVaultManagerEvent {
    function vaultOf(uint vID) external view returns(VaultData memory result);
    function validVault(uint vID) external view returns(bool);
    function createVault(VaultData calldata data) external returns(uint);
    function destroyVault(uint vID) external;
    function vaultId(address botToken, uint8 vaultIndex) external pure returns(uint);
    function registerHandler(bytes4 vaultType, IBotVault handler) external;
    function setBotManager(address botManager) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DABotCommon.sol"; 
import "./IDABotController.sol";
import "./IDABotSettingModule.sol";
import "./IDABotStakingModule.sol";
import "./IDABotGovernModule.sol";
import "./IDABotFundManagerModule.sol";

interface IDABot is IDABotController, 
    IDABotSettingModule, 
    IDABotStakingModule, 
    IDABotGovernModule, 
    IDABotFundManagerModule 
{
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../token/IRoboFiERC20.sol";
import "../DABotCommon.sol";

interface IDABotCertLocker is IRoboFiERC20 {
    function asset() external view returns(IRoboFiERC20);
    function detail() external view returns(LockerInfo memory);
    function lockedBalance() external view returns(uint);
    function unlockerable() external view returns(bool);
    function tryUnlock() external returns(bool, uint);
    function finalize() external payable;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDABotCertToken is IERC20 {

    /**
    @dev Gets the total deposit of the underlying asset within this certificate.
     */
    function totalStake() external view returns(uint);

    /**
    @dev Queries the bot who owned this certificate.
     */
    function owner() external view returns(address);
    
    /**
    @dev Gets the underlying asset of this certificate.
     */
    function asset() external view returns (IERC20);
    
    /**
    @dev Returns the equivalent amount of the underlying asset for the given amount
        of certificate tokens.
    @param amount - the amount of certificate tokens.
     */
    function value(uint amount) external view returns(uint);

    /**
    @dev Mints an amount of certificate tokens to the given amount. The equivalent of
        underlying asset should be tranfered to this certificate contract by the caller.
    @param account - the address to recieve minted tokens.
    @param amount - the amount of tokens to mint.
    @notice Only the owner bot can call this function.
     */
    function mint(address account, uint amount) external;

    /**
    @dev Burns an amount of certificate tokens, and returns the equivalant amount of
        the underlying asset to the specified account.
    @param account - the address holing certificate tokens to burn.
    @param amount - the amount of certificate token to burn.
    @return the equivalent amount of underlying asset tranfered to the specified account.
    @notice Only the owner bot can call this function.
     */
    function burn(address account, uint amount) external returns (uint);

    /**
    @dev Burns an amount of certificate tokens, and returns the equivalent amount of the 
        underlying asset to the caller.
    @param amount - the amount of certificate token to burn.
    @return the equivalent amount of underlying asset transfered to the caller.
     */
    function burn(uint amount) external returns(uint);

    /**
    @dev Burns an amount of certificate tokens without returning any underlying assets.
    @param account - the account holding certificate tokens to burn.
    @param amount - the amount of certificate tokens to burn.
    @notice Only owner bot can call this function.
     */
    function slash(address account, uint amount) external;

    /**
    @dev Compound a given amount of the underlying asset to the total deposit. 
        The compoud could be either profit or loss.
    @param amount - the compound amount.
    @param profit - `true` to increase the total deposit, `false` to decrease.
     */
    function compound(uint amount, bool profit) external;

    /**
    @dev Deletes this certificate token contracts.
     */
    function finalize() external payable;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DABotCommon.sol"; 

interface IDABotControllerEvent {
    event BotAbandoned(bool value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ModuleHandlerChanged(bytes32 moduleId, address indexed oldModuleAddress, address indexed newModuleAddress);
    event ModuleRegistered(bytes32 moduleId, address indexed moduleAddress, string name, string version);
}

/**
@dev The generic interface of a DABot.
 */
interface IDABotController is IDABotControllerEvent {
    function abandon(bool value) external;
    function governToken() external view returns(address);
    function qualifiedName() external view returns(string memory);
    function metadata() external view returns(BotMetaData memory);
    function setting() external view returns(BotSetting memory);
    function botDetails() view external returns(BotDetail memory);
    function updatePortfolio(address asset, uint maxCap, uint iboCap, uint weight) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../DABotCommon.sol";

bytes32 constant IDABotFundManagerModuleID = keccak256('fundmanager.module');

interface IDABotFundManagerModuleEvent {
    event Award(StakingPNL[] pnl);
    event AwardCompound(address indexed asset, uint amount, uint mode);
    event AwardBenefitciary(address benefitciary, uint amount, uint share, uint totalShare);
}

interface IDABotFundManagerModule is IDABotFundManagerModuleEvent {
    
    /**
    @dev Gets detailed information about benefitciaries of staking rewards.
     */
    function benefitciaries() external view returns(BenefitciaryInfo[] memory result);

    /**
     @dev Add profit/loss for each asset in the portfolio.
     @param pnl - list of StakingPNL data.
     */
    function updatePnl(StakingPNL[] calldata pnl) external;

    /**
    @dev Checks the pending stake rewarod of a given account for specified assets.
    @param account - the account to check.
    @param assets - the list of assets to check for reward. 
        If empty list is passed, all assets in the portfolio are checked.
    @param subVaults - the list of sub-vaults to check. 
        If empty list is passed, all sub vaults (i.e., [0, 1, 2]) are checked.
     */
    function pendingStakeReward(address account, address[] calldata assets, 
        bytes calldata subVaults) external view returns(StakingReward[] memory);

    /**
    @dev Checks the pending governance rewardsof a given account.
    @param account - the account to check.
    @param subVaults - the lst oof sub-vaults to check. 
        if empty list is passed, all sub vaults (i.e., [0, 1]) are checked.
     */
    function pendingGovernReward(address account, bytes calldata subVaults) external view returns(uint);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../DABotCommon.sol";

bytes32 constant IDABotGovernModuleID = keccak256('governance.module');

interface IDABotGovernModuleEvent {
    
}

interface IDABotGovernModule {

    /**
    @dev Creates staking vaults for governance tokens. This method should be called
        internally only by the bot manager.
     */
    function createGovernVaults() external;

    /**
    @dev Gets the maximum amount of gToken that an account could mint from a bot.
    @param account - the account to query.
    @return the total mintable amount of gToken.
     */
    function mintableShare(address account) external view returns(uint);

    /** 
    @dev Gets the details accounting for the amount of mintable shares.
    @param account the account to query
    @return an array of MintableShareDetail strucs.
     */
    function iboMintableShareDetail(address account) external view returns(MintableShareDetail[] memory); 

    /**
    @dev Calculates the output for an account who mints shares with the given VICS amount.
    @param account - the account to query
    @param vicsAmount - the amount of VICS used to mint shares.
    @return payment - the amount of VICS for minting shares.
            shares - the amount of shares mintied.
            fee - the amount of VICS for minting fee. 
     */
    function calcOutShare(address account, uint vicsAmount) external view returns(uint payment, uint shares, uint fee);

    /**
    @dev Get the total balance of shares owned by the specified account. The total includes
        shares within the account's wallet, and shares staked in bot's vaults.
    @param account - the account to query.
    @return the number of shares.
     */
    function shareOf(address account) external view returns(uint);

    /**
    @dev Mints shares for the given VICS amount. Minted shares will directly stakes to BotVault for rewards.
    @param vicsAmount - the amount of VICS used to mint shared.
    @notice
        Minted shares during IBO will be locked in separated pool, which onlly allow users to withdraw
        after 1 month after the IBO ends.

        VICS for payment will be kept inside the share contracts. Whereas, VICS for fee are transfered
        to the tax address, configured in the platform configurator.
     */
    function mintShare(uint vicsAmount) external;

    /**
    @dev Burns an amount of gToken and sends the corresponding VICS to caller's wallet.
    @param amount - the amount of gToken to burn.
     */
    function burnShare(uint amount) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDABotGovernToken is IERC20 {

    function owner() external view returns(address);
    function asset() external view returns (IERC20);
    function value(uint amount) external view returns(uint);
    function mint(address account, uint amount) external;
    function burn(uint amount) external returns(uint);

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IBotVault.sol";
import "../DABotCommon.sol";
import "../../common/IRoboFiFactory.sol";
import "../../common/IConfigurator.sol";
interface IDABotManager {
    
    function configurator() external view returns(IConfigurator);
    function vaultManager() external view returns(IBotVaultManager);
    function addTemplate(address template) external;
    function templates() external view returns(address[] memory);
    function isRegisteredTemplate(address template) external view returns(bool);
    function isRegisteredBot(address account) external view returns(bool);
    function totalBots() external view returns(uint);
    function botIdOf(string calldata qualifiedName) external view returns(int);
    function queryBots(uint[] calldata botId) external view returns(BotDetail[] memory output);
    function deployBot(address template, 
                        string calldata symbol, 
                        string calldata name,
                        BotModuleInitData[] calldata initData
                        ) external;

    event BotDeployed(uint botId, address indexed bot, BotDetail detail); 
    event TemplateRegistered(address indexed template, string name, string version, uint8 templateType);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
@dev An common interface of a DABot module.
 */
interface IDABotModule {
    function moduleInfo() external view returns(string memory name, string memory version, bytes32 moduleId);
    function onRegister(address moduleAddress) external;
    function onInitialize(bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../DABotCommon.sol";

bytes32 constant IDABotSettingModuleID = keccak256('setting.module');

interface IDABotSettingModuleEvent {
    event SettingChanged(uint what, BotSetting setting);  
    event AddressWritten(bytes32 itemId, address indexed value);
    event UintWritten(bytes32 itemId, uint value);
    event BytesWritten(bytes32 itemId, bytes value);
}

interface IDABotSettingModule is IDABotSettingModuleEvent {   
    function status() external view returns(uint);
    function iboTime() external view returns(uint startTime, uint endTime);
    function stakingTime() external view returns(uint warmup, uint cooldown);
    function pricePolicy() external view returns(uint priceMul, uint commission);
    function profitSharing() external view returns(uint128);
    function setIBOTime(uint startTime, uint endTime) external;
    function setStakingTime(uint warmup, uint cooldown, uint unit) external;
    function setPricePolicy(uint priceMul, uint commission) external;
    function setProfitSharing(uint sharingScheme) external;

    function readAddress(bytes32 itemId, address defaultAddress) external view returns(address);
    function readUint(bytes32 itemId, uint defaultValue) external view returns(uint);
    function readBytes(bytes32 itemId, bytes calldata defaultValue) external view returns(bytes memory);

    function writeAddress(bytes32 itemId, address value) external;
    function writeUint(bytes32 itemId, uint value) external;
    function writeBytes(bytes32 itemId, bytes calldata value) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IDABotCertToken.sol";
import "../DABotCommon.sol";

bytes32 constant IDABotStakingModuleID = keccak256("staking.module");

interface IDABotStakingModuleEvent {
     event PortfolioUpdated(address indexed asset, address indexed certToken, uint maxCap, uint iboCap, uint weight);
     event AssetRemoved(address indexed asset, address indexed certToken);   
     event Stake(address indexed asset, uint amount, address indexed certToken, uint certAmount, address indexed locker);
     event Unstake(address indexed certToken, uint certAmount, address indexed asset, address indexed locker);
}

interface IDABotStakingModule is IDABotStakingModuleEvent {

     /**
     @dev Gets the detailed information of the bot's portfolio.
     @return the arrays of UserPortfolioAsset struct.
      */
     function portfolioDetails() external view returns(UserPortfolioAsset[] memory);

     /**
     @dev Gets the portfolio information for the given asset.
     @param asset - the asset to query.
      */
     function portfolioOf(address asset) external view returns(UserPortfolioAsset memory);

     /**
     @dev Adds or update an asset in the bot's portfolio.
     @param asset - the crypto asset to add/update in the portfolio.
     @param maxCap - the maximum amount of crypto asset to stake to the bot.
     @param iboCap - the maximum amount of crypto asset to stake during the bot's IBO.
     @param weight - the preference index of an asset in the portfolio. This is used
               to calculate the mintable amount of governance shares in accoardance to 
               staked amount. 

               Gven the same USD-worth amount of two assets, the one with higher weight 
               will contribute more to the mintable amount of shares than the other.
      */
     function updatePortfolioAsset(address asset, uint maxCap, uint iboCap, uint weight) external;

     /**
     @dev Removes an asset from the bot's portfolio.
     @param asset - the crypto asset to remove.
     @notice asset could only be removed before the IBO. After that, asset could only be
               remove if there is no tokens of this asset staked to the bot.
      */
     function removePortfolioAsset(address asset) external;

     /**
     @dev Creates vaults for each asset in the portfolio. This method should be called 
          internally by the bot manager.
      */
     function createPortfolioVaults() external;

     /**
     @dev Gets the maximum amount of crypto asset that could be staked  to the bot.
     @param asset - the crypto asset to check.
     @return the maximum amount of crypto asset to stake.
      */
     function getMaxStake(address asset) external returns(uint);

     /**
     @dev Stakes an amount of crypto asset to the bot to receive staking certificate tokens.
     @param asset - the asset to stake.
     @param amount - the amount to stake.
      */
     function stake(address asset, uint amount) external;

     /**
     @dev Burns an amount of staking certificates to get back underlying asset.
     @param certToken - the certificate to burn.
     @param amount - the amount to burn.
      */
     function unstake(IDABotCertToken certToken, uint amount) external;

     /**
     @dev Gets the total staking balance of an account for the specific asset.
          The balance includes pending stakes (i.e., warmup) and excludes 
          pending unstakes (i.e., cooldown)
     @param account - the account to query.
     @param asset - the crypto asset to query.
     @return the total staked amount of the asset.
      */
     function stakeBalanceOf(address account, address asset) external view returns(uint);

     /**
     @dev Gets the total pending stake balance of an account for the specific asset.
     @param account - the account to query.
     @param asset - the asset to query.
     @return the total pending stake.
      */
     function warmupBalanceOf(address account, address asset) external view returns(uint);

     /**
     @dev Gets to total pending unstake balance of an account for the specific certificate.
     @param account - the account to query.
     @param certToken - the certificate token to query.
     @return the total pending unstake.
      */
     function cooldownBalanceOf(address account, address certToken) external view returns(uint);

     /**
     @dev Gets the certificate contract of an asset of a bot.
     @param asset - to crypto asset to query.
     @return the address of the certificate contract.
      */
     function certificateOf(address asset) external view returns(address);

     /**
     @dev Gets the underlying asset of a certificate.
     @param certToken - the address of the certificate contract.
     @return the address of the underlying crypto asset.
      */
     function assetOf(address certToken) external view returns(address);

     /**
     @dev Determines whether an account is a certificate locker.
     @param account - the account to check.
     @return true - if the account is an certificate locker instance creatd by the bot.
      */
     function isCertLocker(address account) external view returns(bool);

     /**
     @dev Gets the details of lockers for pending stake.
     @param account - the account to query.
     @return the array of LockerInfo struct.
      */
     function warmupDetails(address account) external view returns(LockerInfo[] memory);

     /**
     @dev Gets the details of lockers for pending unstake.
     @param account - the account to query.
     @return the array of LockerInfo struct.
      */
     function cooldownDetails(address account) external view returns(LockerInfo[] memory);

     /**
     @dev Releases tokens in all pending stake lockers. 
     @notice At most 20 lockers are unlocked. If the caller has more than 20, additional 
          transactions are required.
      */
     function releaseWarmups() external;

     /**
     @dev Releases token in all pending unstake lockers.
     @notice At most 20 lockers are unlocked. If the caller has more than 20, additional 
          transactions are required.
      */
     function releaseCooldown() external;

     
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IDABotSettingModule.sol";
import "../controller/DABotControllerLib.sol";
import "../DABotCommon.sol";

string constant ERR_ABANDONED = "DABot: bot abandoned";

struct SettingStorage { 
    mapping(bytes32 => address) addrStorage;
    mapping(bytes32 => uint) uintStorage;
    mapping(bytes32 => bytes) blobStorage;
}

library DABotSettingLib {

    string constant ERR_OWNER_REQUIRED = "Setting: owner required"; 
    string constant ERR_VOTE_CONTROLLER_REQUIRED = "Setting: vote controller required";


    using DABotSettingLib for BotSetting;
    using DABotMetaLib for BotMetaData;

    bytes32 constant CORE_STORAGE_POSITION = keccak256("core.dabot.storage");
    bytes32 constant SETTING_STORAGE_POSITION = keccak256("setting.dabot.storage");

    function coredata() internal pure returns(BotCoreData storage ds) {
        bytes32 position = CORE_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setting() internal view returns(BotSetting storage) {
        return coredata().setting;
    }

    function settingStorage() internal pure returns(SettingStorage storage ds) {
        bytes32 position = SETTING_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function status(BotSetting storage _setting) internal view returns(BotStatus result) {
        BotMetaData storage meta = DABotMetaLib.metadata();

        if (meta.abandoned) return BotStatus.ABANDONED;
        if (block.timestamp < _setting.iboStartTime()) return BotStatus.PRE_IBO;
        if (block.timestamp < _setting.iboEndTime()) return BotStatus.IN_IBO;
        return BotStatus.ACTIVE;
    }

    /**
    @dev Ensures that following conditions are met
        1) bot is not abandoned, and
        2) either bot is pre-ibo stage and sender is bot owner, or the sender is vote controller module
     */
    function requireSettingChangable(address account) internal view {
        BotMetaData storage _metadata = DABotMetaLib.metadata();
        
        require(!_metadata.abandoned, ERR_ABANDONED);

        if (_metadata.isTemplate) {
            require(account == _metadata.botOwner, ERR_OWNER_REQUIRED);
            return;
        }

        BotSetting storage _setting = DABotSettingLib.setting();
        if (block.timestamp < _setting.iboStartTime()) {
            require(account == _metadata.botOwner, ERR_OWNER_REQUIRED);
            return;
        }
        address voteController = _metadata.module(BOT_MODULE_VOTE_CONTROLER);
        require(account == voteController, ERR_VOTE_CONTROLLER_REQUIRED);
    }

    function readAddress(SettingStorage storage ds, bytes32 itemId, address defaultAddress) internal view returns(address result) {
        result = ds.addrStorage[itemId]; 
        if (result == address(0)) { 
            BotMetaData storage _metadata = DABotMetaLib.metadata();
             if (_metadata.botManager == address(0))
                return result;
            if (_metadata.botTemplate != address(0))
                result = IDABotSettingModule(_metadata.botTemplate).readAddress(itemId, defaultAddress);
            if (result == address(0))
                result = _metadata.configurator().addressOf(itemId);
            if (result == address(0))
                result = defaultAddress;
        }
    }

    function writeAddress(SettingStorage storage ds, bytes32 itemId, address value) internal {
        ds.addrStorage[itemId] = value;
    }

    function readUint(SettingStorage storage ds, bytes32 itemId, uint defaultValue) internal view returns(uint result) {
        result = ds.uintStorage[itemId];
        if (result == 0) {
            BotMetaData storage _metadata = DABotMetaLib.metadata();
            if (_metadata.botManager == address(0))
                return result;
            if (_metadata.botTemplate != address(0))
                result = IDABotSettingModule(_metadata.botTemplate).readUint(itemId, defaultValue);
            if (result == 0)
                result = _metadata.configurator().configOf(itemId);
            if (result == 0)
                result = defaultValue;
        }

    }

    function writeUint(SettingStorage storage ds, bytes32 itemId, uint value) internal {
        ds.uintStorage[itemId] = value;
    }

    function readBytes(SettingStorage storage ds, bytes32 itemId, bytes calldata defaultValue) internal view returns(bytes memory result) {
        result = ds.blobStorage[itemId];
        if (result.length == 0) {
            BotMetaData storage _metadata = DABotMetaLib.metadata();
            if (_metadata.botManager == address(0))
                return result;
            if (_metadata.botTemplate != address(0))
                result = IDABotSettingModule(_metadata.botTemplate).readBytes(itemId, defaultValue);
            if (result.length == 0)
                result = _metadata.configurator().bytesConfigOf(itemId);
            if (result.length == 0)
                result = defaultValue;
        }
    }

    function writeBytes(SettingStorage storage ds, bytes32 itemId, bytes calldata defaultValue) internal {
        ds.blobStorage[itemId] = defaultValue;
    }

    function iboStartTime(BotSetting memory info) internal pure returns(uint) {
        return info.iboTime & 0xFFFFFFFF;
    }

    function iboEndTime(BotSetting memory info) internal pure returns(uint) {
        return info.iboTime >> 32;
    }

    function setIboTime(BotSetting storage info, uint start, uint end) internal {
        require(start < end, "invalid ibo start/end time");
        info.iboTime = uint64((end << 32) | start);
    }

    function warmupTime(BotSetting storage info) internal view returns(uint) {
        return info.stakingTime & 0xFF;
    }

    function cooldownTime(BotSetting storage info) internal view returns(uint) {
        return (info.stakingTime >> 8) & 0xFF;
    }

    function getStakingTimeMultiplier(BotSetting storage info) internal view returns (uint) {
        uint unit = stakingTimeUnit(info);
        if (unit == 0) return 1 days;
        if (unit == 1) return 1 hours;
        if (unit == 2) return 1 minutes;
        return 1 seconds;
    }

    function stakingTimeUnit(BotSetting storage info) internal view returns (uint) {
        return (info.stakingTime >> 16);
    }

    function setStakingTime(BotSetting storage info, uint warmup, uint cooldown, uint unit) internal {
        info.stakingTime = uint24((unit << 16) | (cooldown << 8) | warmup);
    }

    function priceMultiplier(BotSetting storage info) internal view returns(uint) {
        return info.pricePolicy & 0xFFFF;
    }

    function commission(BotSetting storage info) internal view returns(uint) {
        return info.pricePolicy >> 16;
    }

    function setPricePolicy(BotSetting storage info, uint _priceMul, uint _commission) internal {
        info.pricePolicy = uint32((_commission << 16) | _priceMul);
    }

    function profitShare(BotSetting storage info, uint actor) internal view returns(uint) {
        return (info.profitSharing >> actor * 16) & 0xFFFF;
    }

    function setProfitShare(BotSetting storage info, uint sharingScheme) internal {
        info.profitSharing = uint128(sharingScheme);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../token/IRoboFiERC20.sol";
import "../interfaces/IDABotCertLocker.sol";
import "../interfaces/IDABotCertToken.sol";
import "../DABotCommon.sol";
import "../controller/DABotControllerLib.sol";

string constant ERR_PRE_IBO_OPERATION = "Staking: operation is only supported in pre-IBO";
string constant ERR_AFTER_IBO_OPERATION = "Staking: operation is only supported in after-IBO";
string constant ERR_INVALID_PORTFOLIO_ASSET = "Staking: invalid portfolio asset"; 
string constant ERR_PORTFOLIO_FULL = "Staking: portfolio is full";
string constant ERR_INVALID_CERTIFICATE_ASSET = "Staking: invalid certificate asset";
string constant ERR_PORTFOLIO_ASSET_NOT_FOUND = "Staking: asset is not in portfolio";
string constant ERR_ZERO_ASSET = "Staking: asset is zero";
string constant ERR_INVALID_STAKING_CAP = "Staking: invalid cap";
string constant ERR_INSUFFICIENT_FUND = "Staking: insufficient fund";
string constant ERR_ZERO_CAP = "Staking: zero cap";
string constant ERR_INVALID_CAP = "Staking: cap is less than stake and ibo cap";
string constant ERR_ZERO_WEIGHT = "Staking: zero weight";

struct BotStakingData {
    IRoboFiERC20[]  assets; 
    mapping(IRoboFiERC20 => PortfolioAsset) portfolio;
    mapping(address => IDABotCertLocker[]) warmup;
    mapping(address => IDABotCertLocker[]) cooldown;
    mapping(address => bool) lockers;
}

library DABotStakingLib {
    bytes32 constant STAKING_STORAGE_POSITION = keccak256("staking.dabot.storage");

    using DABotStakingLib for BotStakingData;
    using DABotMetaLib for BotMetaData;

    function staking() internal pure returns(BotStakingData storage ds) {
        bytes32 position = STAKING_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function stakeBalanceOf(BotStakingData storage ds, address account, IRoboFiERC20 asset) internal view returns(uint) {
        BotMetaData storage meta = DABotMetaLib.metadata();
        IBotVaultManager vault = IDABotManager(meta.botManager).vaultManager();
        IDABotCertToken certToken = ds.certificateOf(asset);
        uint vID = vault.vaultId(address(certToken), 0);

        return certToken.balanceOf(account)
                + ds.warmupBalanceOf(account, asset)
                + vault.balanceOf(vID, account)
                + vault.balanceOf(vID + 1, account)
                + vault.balanceOf(vID + 2, account)
                - ds.cooldownBalanceOf(account, ds.certificateOf(asset));
    }

    function totalStake(BotStakingData storage ds, IRoboFiERC20 asset) internal view returns(uint) {
        return IDABotCertToken(ds.portfolio[asset].certToken).totalStake();
    }

    function warmupBalanceOf(BotStakingData storage ds, address account, IRoboFiERC20 asset) internal view returns(uint) {
        IDABotCertLocker[] storage lockers = ds.warmup[account];
        return lockedBalance(lockers, address(asset));
    }

    function cooldownBalanceOf(BotStakingData storage ds, address account, IDABotCertToken certToken) internal view returns(uint) {
        IDABotCertLocker[] storage lockers = ds.cooldown[account];
        return lockedBalance(lockers, address(certToken.asset()));
    }
    
    function certificateOf(BotStakingData storage ds, IRoboFiERC20 asset) internal view returns(IDABotCertToken) {
        return IDABotCertToken(ds.portfolio[asset].certToken); 
    }

    function assetOf(address certToken) public view returns(IERC20) {
        return IDABotCertToken(certToken).asset(); 
    }

    function lockedBalance(IDABotCertLocker[] storage lockers, address asset) internal view returns(uint result) {
        result = 0;
        for (uint i = 0; i < lockers.length; i++) 
            if (address(lockers[i].asset()) == asset)
                result += lockers[i].lockedBalance();
    }

    function portfolioDetails(BotStakingData storage ds) internal view returns(UserPortfolioAsset[] memory output) {
        output = new UserPortfolioAsset[](ds.assets.length);
        for(uint i = 0; i < ds.assets.length; i++) {
            IRoboFiERC20 asset = ds.assets[i];
            output[i].asset = address(asset);
            output[i].info = ds.portfolio[asset];
            output[i].userStake = ds.stakeBalanceOf(msg.sender, asset);
            output[i].totalStake = ds.totalStake(asset);
        }
    }

    function portfolioOf(BotStakingData storage ds, IRoboFiERC20 asset) internal view returns(UserPortfolioAsset memory  output) {
        output.asset = address(asset);
        output.info = ds.portfolio[asset];
        output.userStake = ds.stakeBalanceOf(msg.sender, asset);
        output.totalStake = ds.totalStake(asset);
    }

    function updatePortfolioAsset(BotStakingData storage ds, IRoboFiERC20 asset, uint maxCap, uint iboCap, uint weight) internal {
        PortfolioAsset storage pAsset = ds.portfolio[asset];

        if (address(pAsset.certToken) == address(0)) {
            pAsset.certToken = DABotMetaLib.metadata().deployCertToken(address(asset));
            ds.assets.push(asset);
        }

        if (maxCap > 0) pAsset.cap = maxCap;
        if (iboCap > 0) pAsset.iboCap = iboCap;
        if (weight > 0) pAsset.weight = weight;

        uint _totalStake = IDABotCertToken(pAsset.certToken).totalStake();

        require((pAsset.cap >= _totalStake) && (pAsset.cap >= pAsset.iboCap), ERR_INVALID_STAKING_CAP);
    }

    function removePortfolioAsset(BotStakingData storage ds, IRoboFiERC20 asset) internal returns(address) {
        require(address(asset) != address(0), ERR_ZERO_ASSET);
        for(uint i = 0; i < ds.assets.length; i++)
            if (address(ds.assets[i]) == address(asset)) {
                address certToken = ds.portfolio[asset].certToken;
                IDABotCertToken(certToken).finalize(); 
                delete ds.portfolio[asset];
                ds.assets[i] = ds.assets[ds.assets.length - 1];
                ds.assets.pop();
                return certToken;
            }
        revert(ERR_PORTFOLIO_ASSET_NOT_FOUND);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../controller/DABotController.sol";
import "../interfaces/IDABotSettingModule.sol";
import "../interfaces/IDABotStakingModule.sol";
import "../interfaces/IDABotGovernModule.sol";
import "../interfaces/IDABotFundManagerModule.sol";
import "../interfaces/IDABot.sol";
import "../DABotCommon.sol";

import "../fundmanager/DABotFundManagerLib.sol";

contract CEXDABot is DABotModuleController, 
                    IDABotSettingModuleEvent, 
                    IDABotStakingModuleEvent, 
                    IDABotGovernModuleEvent,
                    IDABotFundManagerModuleEvent,
                    IERC165 
{

    using DABotFundManagerLib for FundManagementData;

    constructor(
        address settingModule,
        address stakingModule,
        address governModule,
        address fundManagerModule,
        address certToken,
        address govToken,
        address warmupLocker,
        address cooldownLocker
        ) DABotModuleController('CEX DABot', 'v0.1.210901') 
    {
        registerModule(settingModule);
        registerModule(stakingModule); 
        registerModule(governModule);
        registerModule(fundManagerModule);
        updateModuleHandler(BOT_MODULE_CERTIFICATE_TOKEN, certToken);
        updateModuleHandler(BOT_MODULE_GOVERNANCE_TOKEN, govToken);
        updateModuleHandler(BOT_MODULE_WARMUP_LOCKER, warmupLocker);
        updateModuleHandler(BOT_MODULE_COOLDOWN_LOCKER, cooldownLocker);

        FundManagementData storage fundData = DABotFundManagerLib.fundData();
        fundData.addBenefitciary(BOT_CREATOR_BENEFITCIARY);
        fundData.addBenefitciary(GOV_USER_BENEFITCIARY);
        fundData.addBenefitciary(STAKE_USER_BENEFITCIARY);
    }

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return (interfaceId == type(IERC165).interfaceId) ||
                (interfaceId == type(IDABot).interfaceId)
        ;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRoboFiERC20 is IERC20 {
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

pragma solidity ^0.8.0;

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
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant alphabet = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = alphabet[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 200
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