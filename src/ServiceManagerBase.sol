// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {console} from "forge-std/Test.sol";
import {ServiceManagerBaseStorage} from "./ServiceManagerBaseStorage.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title Minimal implementation of a ServiceManager-type contract.
 * This contract can be inherited from or simply used as a point-of-reference.
 * @author Layr Labs, Inc.
 */
abstract contract ServiceManagerBase is ServiceManagerBaseStorage {
    using BitmapUtils for *;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(_registryCoordinator),
            "ServiceManagerBase.onlyRegistryCoordinator: caller is not the registry coordinator"
        );
        _;
    }

    /// @notice only rewardsInitiator can call createAVSRewardsSubmission
    modifier onlyRewardsInitiator() {
        _checkRewardsInitiator();
        _;
    }

    function _checkRewardsInitiator() internal view {
        require(
            msg.sender == rewardsInitiator,
            "ServiceManagerBase.onlyRewardsInitiator: caller is not the rewards initiator"
        );
    }

    /// @notice Sets the (immutable) `_registryCoordinator` address
    constructor(
        IAVSDirectory __avsDirectory,
        IRewardsCoordinator __rewardsCoordinator,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry
    )
        ServiceManagerBaseStorage(
            __avsDirectory,
            __rewardsCoordinator,
            __registryCoordinator,
            __stakeRegistry
        )
    {
        _disableInitializers();
    }

    function __ServiceManagerBase_init(
        address initialOwner,
        address _rewardsInitiator
    ) internal virtual onlyInitializing {
        _transferOwnership(initialOwner);
        _setRewardsInitiator(_rewardsInitiator);
    }

    /**
     * @notice Updates the metadata URI for the AVS
     * @param _metadataURI is the metadata URI for the AVS
     * @dev only callable by the owner
     */
    function updateAVSMetadataURI(string memory _metadataURI) public virtual onlyOwner {
        _avsDirectory.updateAVSMetadataURI(_metadataURI);
    }

    /**
     * @notice Creates a new rewards submission to the EigenLayer RewardsCoordinator contract, to be split amongst the
     * set of stakers delegated to operators who are registered to this `avs`
     * @param rewardsSubmissions The rewards submissions being created
     * @dev Only callabe by the permissioned rewardsInitiator address
     * @dev The duration of the `rewardsSubmission` cannot exceed `MAX_REWARDS_DURATION`
     * @dev The tokens are sent to the `RewardsCoordinator` contract
     * @dev Strategies must be in ascending order of addresses to check for duplicates
     * @dev This function will revert if the `rewardsSubmission` is malformed,
     * e.g. if the `strategies` and `weights` arrays are of non-equal lengths
     */
    function createAVSRewardsSubmission(IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions)
        public
        virtual
        onlyRewardsInitiator
    {
        for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
            // transfer token to ServiceManager and approve RewardsCoordinator to transfer again
            // in createAVSRewardsSubmission() call
            rewardsSubmissions[i].token.transferFrom(msg.sender, address(this), rewardsSubmissions[i].amount);
            uint256 allowance =
                rewardsSubmissions[i].token.allowance(address(this), address(_rewardsCoordinator));
            rewardsSubmissions[i].token.approve(
                address(_rewardsCoordinator), rewardsSubmissions[i].amount + allowance
            );
        }

        _rewardsCoordinator.createAVSRewardsSubmission(rewardsSubmissions);
    }

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to confirm operator registration with the AVS
     * @param operator The address of the operator to register.
     * @param operatorSignature The signature, salt, and expiry of the operator's signature.
     */
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) public virtual onlyRegistryCoordinator {
        _avsDirectory.registerOperatorToAVS(operator, operatorSignature);
    }

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to confirm operator deregistration from the AVS
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) public virtual onlyRegistryCoordinator {
        _avsDirectory.deregisterOperatorFromAVS(operator);
    }

    /**
     * @notice Sets the rewards initiator address
     * @param newRewardsInitiator The new rewards initiator address
     * @dev only callable by the owner
     */
    function setRewardsInitiator(address newRewardsInitiator) external onlyOwner {
        _setRewardsInitiator(newRewardsInitiator);
    }

    function migrateToOperatorSets() external onlyOwner {
        _migrateToOperatorSets();
    }

    /**
     * @notice Merges two sorted arrays using the merge sort algorithm
     * @param left The first sorted array
     * @param right The second sorted array
     * @return The merged sorted array
     */
    function mergeSortedArrays(uint256[] memory left, uint256[] memory right) internal pure returns (uint256[] memory) {
        uint256 leftLength = left.length;
        uint256 rightLength = right.length;
        uint256[] memory merged = new uint256[](leftLength + rightLength);

        uint256 i = 0; // Index for left array
        uint256 j = 0; // Index for right array
        uint256 k = 0; // Index for merged array

        // Merge the two arrays into the merged array
        while (i < leftLength && j < rightLength) {
            if (left[i] <= right[j]) {
                merged[k] = left[i];
                i++;
            } else {
                merged[k] = right[j];
                j++;
            }
            k++;
        }

        // Copy remaining elements of left, if any
        while (i < leftLength) {
            merged[k] = left[i];
            i++;
            k++;
        }

        // Copy remaining elements of right, if any
        while (j < rightLength) {
            merged[k] = right[j];
            j++;
            k++;
        }

        return merged;
    }

    function _migrateToOperatorSets() internal {
        // Initiate the migration process 
        _avsDirectory.becomeOperatorSetAVS();
        uint256 quorumCount = _registryCoordinator.quorumCount();
        console.log(address(_registryCoordinator), "ServiceManager:RegistryCoord");
        console.log(quorumCount, "ServiceManager: quorumCount");

        address[] memory allOperators = new address[](0);
        uint32[] memory operatorSetIdsToCreate = new uint32[](quorumCount);
        uint32[][] memory operatorSetIds;

        // Step 1: Iterate through quorum numbers and get a list of unique operators
        for (uint8 quorumNumber = 0; quorumNumber < quorumCount; quorumNumber++) {
            // Step 2: Get operator list for quorum at current block
            bytes32[] memory operatorIds = _registryCoordinator.indexRegistry().getOperatorListAtBlockNumber(quorumNumber, uint32(block.number));
        
            // Step 3: Convert to address list and maintain a sorted array of operators
            address[] memory operators = new address[](operatorIds.length);
            for (uint256 i = 0; i < operatorIds.length; i++) {
                operators[i] = _registryCoordinator.blsApkRegistry().getOperatorFromPubkeyHash(operatorIds[i]);
                console.log(operators[i], "ServiceManager: operator");
                // Insert into sorted array of all operators
                allOperators = mergeSortedArrays(allOperators, operators);
            }

            operatorSetIds = new uint32[][](allOperators.length);
            // Loop through each unique operator to get the quorums they are registered for
            for (uint256 i = 0; i < allOperators.length; i++) {
                address operator = allOperators[i];
                bytes32 operatorId = _registryCoordinator.getOperatorId(operator);
                uint192 quorumsBitmap = _registryCoordinator.getCurrentQuorumBitmap(operatorId);
                bytes memory quorumBytesArray = BitmapUtils.bitmapToBytesArray(quorumsBitmap);
                uint32[] memory quorums = new uint32[](quorumBytesArray.length);
                for (uint256 j = 0; j < quorumBytesArray.length; j++) {
                    quorums[j] = uint32(uint8(quorumBytesArray[j]));
                }
                operatorSetIds[i] = quorums;
            }

            operatorSetIdsToCreate[quorumNumber] = uint32(quorumNumber);
        }

        // Step 4: Migrate to operator set for this quorum
        AVSDirectory(address(_avsDirectory)).createOperatorSets(operatorSetIdsToCreate);
        AVSDirectory(address(_avsDirectory)).migrateOperatorsToOperatorSets(allOperators, operatorSetIds);
    }

    /**
     * @notice Merges two sorted arrays of addresses into a single sorted array without duplicates
     * @param left The first sorted array
     * @param right The second sorted array
     * @return The merged sorted array
     */
    function mergeSortedArrays(address[] memory left, address[] memory right) internal pure returns (address[] memory) {
        uint256 leftLength = left.length;
        uint256 rightLength = right.length;
        address[] memory merged = new address[](leftLength + rightLength);

        uint256 i = 0; // Index for left array
        uint256 j = 0; // Index for right array
        uint256 k = 0; // Index for merged array

        // Merge the two arrays into the merged array
        while (i < leftLength && j < rightLength) {
            if (left[i] < right[j]) {
                merged[k++] = left[i++];
            } else if (left[i] > right[j]) {
                merged[k++] = right[j++];
            } else {
                merged[k++] = left[i++];
                j++;
            }
        }

        // Copy remaining elements of left, if any
        while (i < leftLength) {
            merged[k++] = left[i++];
        }

        // Copy remaining elements of right, if any
        while (j < rightLength) {
            merged[k++] = right[j++];
        }

        // Resize the merged array to remove unused space
        assembly { mstore(merged, k) }

        return merged;
    }

    function _setRewardsInitiator(address newRewardsInitiator) internal {
        emit RewardsInitiatorUpdated(rewardsInitiator, newRewardsInitiator);
        rewardsInitiator = newRewardsInitiator;
    }

    /**
     * @notice Returns the list of strategies that the AVS supports for restaking
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on uniqueness of each element in the returned array.
     *      The off-chain service should do that validation separately
     */
    function getRestakeableStrategies() external view returns (address[] memory) {
        uint256 quorumCount = _registryCoordinator.quorumCount();

        if (quorumCount == 0) {
            return new address[](0);
        }

        uint256 strategyCount;
        for (uint256 i = 0; i < quorumCount; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(i));
        }

        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
        for (uint256 i = 0; i < _registryCoordinator.quorumCount(); i++) {
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(uint8(i));
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] =
                    address(_stakeRegistry.strategyParamsByIndex(uint8(i), j).strategy);
                index++;
            }
        }
        return restakedStrategies;
    }

    /**
     * @notice Returns the list of strategies that the operator has potentially restaked on the AVS
     * @param operator The address of the operator to get restaked strategies for
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on whether the operator has shares for a strategy in a quorum or uniqueness
     *      of each element in the returned array. The off-chain service should do that validation separately
     */
    function getOperatorRestakedStrategies(address operator)
        external
        view
        returns (address[] memory)
    {
        bytes32 operatorId = _registryCoordinator.getOperatorId(operator);
        uint192 operatorBitmap = _registryCoordinator.getCurrentQuorumBitmap(operatorId);

        if (operatorBitmap == 0 || _registryCoordinator.quorumCount() == 0) {
            return new address[](0);
        }

        // Get number of strategies for each quorum in operator bitmap
        bytes memory operatorRestakedQuorums = BitmapUtils.bitmapToBytesArray(operatorBitmap);
        uint256 strategyCount;
        for (uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(operatorRestakedQuorums[i]));
        }

        // Get strategies for each quorum in operator bitmap
        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
        for (uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            uint8 quorum = uint8(operatorRestakedQuorums[i]);
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(quorum);
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] =
                    address(_stakeRegistry.strategyParamsByIndex(quorum, j).strategy);
                index++;
            }
        }
        return restakedStrategies;
    }

    /// @notice Returns the EigenLayer AVSDirectory contract.
    function avsDirectory() external view override returns (address) {
        return address(_avsDirectory);
    }
}
