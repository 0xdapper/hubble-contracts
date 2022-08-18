// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.9;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20PresetMinterPauserUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/presets/ERC20PresetMinterPauserUpgradeable.sol";

contract VUSD is ERC20PresetMinterPauserUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 private constant PRECISION = 6;

    /// @notice vUSD is backed 1:1 with reserveToken (USDC)
    IERC20 public immutable reserveToken;

    struct Withdrawal {
        address usr;
        uint amount;
    }
    Withdrawal[] public withdrawals;

    /// @dev withdrawals will start processing at withdrawals[start]
    uint public start;

    /// @dev Constrained by block gas limit
    uint public maxWithdrawalProcesses;

    uint256[50] private __gap;

    constructor(address _reserveToken) {
        require(_reserveToken != address(0), "vUSD: null _reserveToken");
        reserveToken = IERC20(_reserveToken);
    }

    function initialize(string memory name, string memory symbol)
        public
        virtual
        override
    {
        super.initialize(name, symbol); // has initializer modifier
        _revokeRole(MINTER_ROLE, _msgSender()); // __ERC20PresetMinterPauser_init_unchained grants this but is not required
        maxWithdrawalProcesses = 100;
    }

    function mintWithReserve(address to, uint amount) external whenNotPaused {
        reserveToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function withdraw(uint amount) external whenNotPaused {
        require(amount >= 5 * (10**PRECISION), "min withdraw is 5 vusd");
        burn(amount);
        withdrawals.push(Withdrawal(msg.sender, amount));
    }

    function processWithdrawals() external whenNotPaused nonReentrant {
        uint reserve = reserveToken.balanceOf(address(this));
        require(
            reserve >= withdrawals[start].amount,
            "Cannot process withdrawals at this time: Not enough balance"
        );
        uint i = start;
        while (i < withdrawals.length && (i - start) < maxWithdrawalProcesses) {
            Withdrawal memory withdrawal = withdrawals[i];
            if (reserve < withdrawal.amount) {
                break;
            }
            reserve -= withdrawal.amount;
            reserveToken.safeTransfer(withdrawal.usr, withdrawal.amount);
            i += 1;
        }
        start = i;
    }

    function withdrawalQueue()
        external
        view
        returns (Withdrawal[] memory queue)
    {
        uint l = _min(withdrawals.length - start, maxWithdrawalProcesses);
        queue = new Withdrawal[](l);

        for (uint i = 0; i < l; i++) {
            queue[i] = withdrawals[start + i];
        }
    }

    function decimals() public pure override returns (uint8) {
        return PRECISION;
    }

    function setMaxWithdrawalProcesses(uint _maxWithdrawalProcesses) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "ERC20PresetMinterPauser: must have admin role"
        );
        maxWithdrawalProcesses = _maxWithdrawalProcesses;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
