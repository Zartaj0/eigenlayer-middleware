// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import { OperatorSet } from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import { IAllocationManager } from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import { IDelegationManager } from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import { IStrategy } from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import { Merkle } from "eigenlayer-contracts/src/contracts/libraries/Merkle.sol";

import { BN254 } from "./libraries/BN254.sol";

import { IOperatorSetRootCalculator } from "./interfaces/IOperatorSetRootCalculator.sol";
import { IBLSApkRegistry } from "./interfaces/IBLSApkRegistry.sol";
import { IStakeRegistry } from "./interfaces/IStakeRegistry.sol";

contract BLSOperatorSetRootCalculator is IOperatorSetRootCalculator {
    using BN254 for BN254.G1Point;
    using Merkle for bytes32[];
    
    IDelegationManager public immutable delegationManager;
    IAllocationManager public immutable allocationManager;

    IBLSApkRegistry public immutable blsApkRegistry;
    IStakeRegistry public immutable stakeRegistry;

    constructor(
        IAllocationManager _allocationManager,
        IStakeRegistry _stakeRegistry,
        IDelegationManager _delegationManager,
        IBLSApkRegistry _blsApkRegistry
    ) {
        allocationManager = _allocationManager;
        stakeRegistry = _stakeRegistry;
        delegationManager = _delegationManager;
        blsApkRegistry = _blsApkRegistry;
    }

    /**
	 * @notice called offchain by provers in order to get the operatorSetRoot
	 * @param operatorSet the operatorSet to get the operatorSetRoot for
	 * @return the operatorSetRoot
	 */
	function getOperatorLeaves(
		OperatorSet calldata operatorSet
	) external view returns(bytes32) {
        // Get operators
        address[] memory operators = allocationManager.getMembers(operatorSet);

        // Get strategy params. TODO: replace this is gross
        IStakeRegistry.StrategyParams[] memory strategyParams = new IStakeRegistry.StrategyParams[](stakeRegistry.strategyParamsLength(uint8(operatorSet.id)));
        IStrategy[] memory strategies = new IStrategy[](strategyParams.length);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            strategyParams[i] = stakeRegistry.strategyParamsByIndex(uint8(operatorSet.id), i);
            strategies[i] = strategyParams[i].strategy;
        }

        // Get delegated stake
        uint256[][] memory delegatedStake = delegationManager.getOperatorsShares(operators, strategies);
        // Get slashable stake
        uint256[][] memory slashableStake = allocationManager.getMinimumSlashableStake(operatorSet, operators, strategies, uint32(block.number + 14 days / 12 seconds));
        // Get pubkey hashes    
        BN254.G1Point[] memory pubkeys = new BN254.G1Point[](operators.length);
        for (uint256 i = 0; i < operators.length; i++) {
            (pubkeys[i], ) = blsApkRegistry.getRegisteredPubkey(operators[i]);
        }

        uint256 totalDelegatedStake = 0;
        uint256 totalSlashableStake = 0;
        BN254.G1Point memory aggPubkey = BN254.G1Point(0, 0);
        // Get operator leaves
        bytes32[] memory leaves = new bytes32[](operators.length);
        for (uint256 i = 0; i < operators.length; i++) {
            // add to totals
            totalDelegatedStake += delegatedStake[i][operatorSet.id];
            totalSlashableStake += slashableStake[i][operatorSet.id];
            aggPubkey = aggPubkey.plus(pubkeys[i]);

            // get operator leaf
            leaves[i] = keccak256(abi.encodePacked(
                totalDelegatedStake,
                totalSlashableStake,
                aggPubkey.X,
                aggPubkey.Y
            ));
        }

        // get operator tree root
        bytes32 operatorTreeRoot = leaves.merkleizeKeccak256();

        // get operator set root
        bytes32 operatorSetRoot = keccak256(abi.encodePacked(
            operatorTreeRoot,
            keccak256(abi.encodePacked(
                totalDelegatedStake,
                totalSlashableStake,
                aggPubkey.X,
                aggPubkey.Y
            ))
        ));

        return operatorSetRoot;
	}
}