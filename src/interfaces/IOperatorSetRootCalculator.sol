// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import { OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

interface IOperatorSetRootCalculator {
	/**
	 * @notice called offchain by provers in order to get the operatorSetRoot
	 * @param operatorSet the operatorSet to get the operatorSetRoot for
	 * @return the operatorSetRoot
	 */
	function getOperatorLeaves(
		OperatorSet calldata operatorSet
	) external view returns(bytes32);
}