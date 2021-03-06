pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./SERToken.sol";

// MasterChef is the master of SER. He can make SER and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SER is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract Pool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SERs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSERPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSERPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SERs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SERs distribution occurs.
        uint256 accSERPerShare; // Accumulated SERs per share, times 1e12. See below.
        uint256 minAMount;
        uint256 maxAMount;
    }

    // The SER TOKEN!
    SERToken public SER;
    // Dev address.
    address public devaddr;
    // Operation address.
    address public operationaddr;
    // Fund address.
    address public fundaddr;
    // institution address.
    address public institutionaddr;
    // Block number when bonus SER period ends.
    uint256 public bonusEndBlock;
    // SER tokens created per block.
    uint256 public SERPerBlock;
    // Bonus muliplier for early SER makers.
    uint256 public constant BONUS_MULTIPLIER = 10;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SER mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDev(address indexed devAddress);
    event SetSERPerBlock(uint256 _SERPerBlock);
    event SetMigrator(address _migrator);
    event SetOperation(address _operation);
    event SetFund(address _fund);
    event SetInstitution(address _institution);
    event SetPool(uint256 pid ,address lpaddr,uint256 point,uint256 min,uint256 max);
    constructor(
        SERToken _SER,
        address _devaddr,
        address _operationaddr,
        address _fundaddr,
        address _institutionaddr,
        uint256 _SERPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        SER = _SER;
        devaddr = _devaddr;
        SERPerBlock = _SERPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        operationaddr = _operationaddr;
        fundaddr = _fundaddr;
        institutionaddr = _institutionaddr;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setSERPerBlock(uint256 _SERPerBlock) public onlyOwner {
        SERPerBlock = _SERPerBlock;
        emit SetSERPerBlock(_SERPerBlock);
    }

    function GetPoolInfo(uint256 id) external view returns (PoolInfo memory) {
        return poolInfo[id];
    }

    function GetUserInfo(uint256 id,address addr) external view returns (UserInfo memory) {
        return userInfo[id][addr];
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate,uint256 _min,uint256 _max) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accSERPerShare: 0,
            minAMount:_min,
            maxAMount:_max
        }));
        emit SetPool(poolInfo.length-1 , address(_lpToken), _allocPoint, _min, _max);
    }

    // Update the given pool's SER allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate,uint256 _min,uint256 _max) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].minAMount = _min;
        poolInfo[_pid].maxAMount = _max;
        emit SetPool(_pid , address(poolInfo[_pid].lpToken), _allocPoint, _min, _max);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    // 获取年化率 以SER为单位的币本位计算
    function getApy(uint256 _pid) public view returns (uint256) {
        uint256 yearCount = SERPerBlock.mul(86400).div(3).mul(365);
        return yearCount.div(getTvl(_pid));
    }

    // 获取总量 以SER为单位的币本位
    function getTvl(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        (uint256 t1,uint256 t2,) = IUniswapV2Pair(address(pool.lpToken)).getReserves();
        address token0 = IUniswapV2Pair(address(pool.lpToken)).token0();
        uint256 allCount = 0;
        if(token0==address(SER)){ // 总成本
            allCount = t1.mul(2);
        } else{
            allCount = t2.mul(2);
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 totalSupply = pool.lpToken.totalSupply();
        return allCount.mul(lpSupply).div(totalSupply);
    }

    // View function to see pending SERs on frontend.
    function pendingSER(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSERPerShare = pool.accSERPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 SERReward = multiplier.mul(SERPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accSERPerShare = accSERPerShare.add(SERReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accSERPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 SERReward = multiplier.mul(SERPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        uint256 devReward = SERReward.mul(38);
        SER.mint(devaddr, devReward.div(100)); // 38% Development
        SER.mint(operationaddr, SERReward.div(8)); // 12% Operation
        SER.mint(fundaddr, SERReward.div(4)); // 25% Growth Fund

        uint256 institutionReward = SERReward.mul(75);
        SER.mint(institutionaddr,institutionReward.div(100)); // 75% Institution Node

        SER.mint(address(this), SERReward); // Liquidity reward
        pool.accSERPerShare = pool.accSERPerShare.add(SERReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for SER allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accSERPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeSERTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            if (pool.minAMount > 0 && user.amount < pool.minAMount){
                revert("amount is too low");
            }
            if (pool.maxAMount > 0 && user.amount > pool.maxAMount){
                revert("amount is too high");
            }
        }
        user.rewardDebt = user.amount.mul(pool.accSERPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSERPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeSERTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSERPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe SER transfer function, just in case if rounding error causes pool to not have enough SERs.
    function safeSERTransfer(address _to, uint256 _amount) internal {

        uint256 SERBal = SER.balanceOf(address(this));
        
        if (_amount > SERBal) {
            SER.transfer(_to, SERBal);
        } else {
            SER.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "_devaddr is address(0)");
        devaddr = _devaddr;
        emit SetDev(_devaddr);
    }

    // Update operation address by the previous operation.
    function operation(address _opaddr) public {
        require(msg.sender == operationaddr, "operation: wut?");
        require(_opaddr != address(0), "_opaddr is address(0)");
        operationaddr = _opaddr;
        emit SetOperation(_opaddr);
    }

    // Update fund address by the previous fund.
    function fund(address _fundaddr) public {
        require(msg.sender == fundaddr, "fund: wut?");
        require(_fundaddr != address(0), "_fundaddr is address(0)");
        fundaddr = _fundaddr;
        emit SetFund(_fundaddr);
    }

    // Update institution address by the previous institution.
    function institution(address _institutionaddr) public {
        require(msg.sender == _institutionaddr, "institution: wut?");
        require(_institutionaddr != address(0), "_institutionaddr is address(0)");
        institutionaddr = _institutionaddr;
        emit SetInstitution(_institutionaddr);
    }
}
