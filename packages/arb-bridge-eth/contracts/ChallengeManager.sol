/*
 * Copyright 2019, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity ^0.5.3;

import "./challenge/IChallengeManager.sol";
import "./challenge/OneStepProof.sol";
import "./challenge/Bisection.sol";

import "./vm/IVMTracker.sol";


contract ChallengeManager is IChallengeManager {

    event ContinuedChallenge (
        address indexed vmAddress,
        address challenger,
        uint assertionIndex
    );

    event BisectedAssertion(
        address indexed vmAddress,
        address bisecter,
        bytes32 preconditionHash,
        bytes32[] bisectionHashes,
        uint32 numSteps
    );

    event BisectedAssertionOther(
        address indexed vmAddress,
        address bisecter,
        bytes32[] bisectionHashes,
        uint32 numSteps,
        uint256[] prevOutputValues
    );

    event OneStepProofCompleted(
        address indexed vmAddress,
        address asserter,
        bytes proof
    );

    event TimedOutChallenge (
        address indexed vmAddress,
        bool challengerWrong
    );

    mapping(address => Challenge.Data) challenges;

    function initiateChallenge(
        address[2] calldata _players,
        uint128[2] calldata _escrows,
        uint32 _challengePeriod,
        bytes32 _challengeRoot
    )
        external
    {
        require(challenges[msg.sender].challengeState == 0x00, "There must be no existing challenge");

        challenges[msg.sender] = Challenge.Data(
            msg.sender,
            _challengeRoot,
            _escrows,
            _players,
            uint64(block.number) + uint64(_challengePeriod),
            _challengePeriod,
            Challenge.State.Challenged
        );
    }

    function bisectAssertionFirst(
        address _challengeId,
        uint32 _numSteps,
        bytes32 _preconditionHash,
        bytes32 _assertionHash,
        bytes32[] memory _bisectionHashes
    )
        public
    {
        Challenge.Data storage challenge = challenges[_challengeId];
        Bisection.bisectAssertionFirst(
            challenge,
            _numSteps,
            _preconditionHash,
            _assertionHash,
            _bisectionHashes
        );
    }

    function bisectAssertionOther(
        address _challengeId,
        bytes32[10] memory _fields,
        uint64[2] memory _timeBounds,
        bytes21[] memory _tokenTypes,
        uint256[] memory _beforeBalances,
        uint32 _a1NumSteps,
        uint256[] memory _a1OutputValues,
        uint32 _a2NumSteps,
        uint256[] memory _a2OutputValues,
        bytes32[] memory _bisectionHashes
    )
        public
    {
        Challenge.Data storage challenge = challenges[_challengeId];
        Bisection.bisectAssertionOther(
            challenge,
            _fields,
            _timeBounds,
            _tokenTypes,
            _beforeBalances,
            _a1NumSteps,
            _a1OutputValues,
            _a2NumSteps,
            _a2OutputValues,
            _bisectionHashes
        );
    }

    function continueChallenge(
        address _vmAddress,
        uint _assertionToChallenge,
        bytes memory _proof,
        bytes32 _bisectionRoot,
        bytes32 _bisectionHash
    )
        public
    {
        Challenge.Data storage challenge = challenges[_vmAddress];
        Bisection.continueChallenge(
            challenge,
            _assertionToChallenge,
            _proof,
            _bisectionRoot,
            _bisectionHash
        );
    }

    function oneStepProofFirst(
        address _vmAddress,
        bytes32[2] memory _beforeHashAndInbox,
        uint64[2] memory _timeBounds,
        bytes21[] memory _tokenTypes,
        uint256[] memory _beforeBalances,
        bytes32[5] memory _afterHashAndMessages,
        uint256[] memory _amounts,
        bytes memory _proof
    )
        public
    {
        Challenge.Data storage challenge = challenges[_vmAddress];
        OneStepProof.oneStepProofFirst(
            challenge,
            _beforeHashAndInbox,
            _timeBounds,
            _tokenTypes,
            _beforeBalances,
            _afterHashAndMessages,
            _amounts,
            _proof
        );
        _asserterWin(challenge);
        emit OneStepProofCompleted(_vmAddress, msg.sender, _proof);
    }

    function oneStepProofOther(
        address _vmAddress,
        bytes32[10] memory _fields,
        uint64[2] memory _timeBounds,
        bytes21[] memory _tokenTypes,
        uint256[] memory _beforeBalances,
        uint32 _a1NumSteps,
        uint256[] memory _a1OutputValues,
        uint32 _a2NumSteps,
        uint256[] memory _a2OutputValues,
        bytes memory _proof
    )
        public
    {
        Challenge.Data storage challenge = challenges[_vmAddress];
        OneStepProof.oneStepProofOther(
            challenge,
            _fields,
            _timeBounds,
            _tokenTypes,
            _beforeBalances,
            _a1NumSteps,
            _a1OutputValues,
            _a2NumSteps,
            _a2OutputValues,
            _proof
        );
        _asserterWin(challenge);
        emit OneStepProofCompleted(_vmAddress, msg.sender, _proof);
    }

    function asserterTimedOut(address _vmAddress) public {
        Challenge.Data storage challenge = challenges[_vmAddress];
        require(
            challenge.state == Challenge.State.Challenged,
            "Can only time out asserter if it is their turn"
        );
        require(block.number > challenge.deadline, "Deadline hasn't expired");

        _challengerWin(challenge);

        emit TimedOutChallenge(_vmAddress, true);
    }

    function challengerTimedOut(address _vmAddress) public {
        Challenge.Data storage challenge = challenges[_vmAddress];
        require(
            challenge.state == Challenge.State.Bisected,
            "Can only time out challenger if it is their turn"
        );
        require(block.number > challenge.deadline, "Deadline hasn't expired");

        _asserterWin(challenge);

        emit TimedOutChallenge(_vmAddress, false);
    }

    function _asserterWin(Challenge.Data storage challenge) private {
        IVMTracker(challenge.vmAddress).completeChallenge(
            challenge.players,
            [
                challenge.escrows[0] + challenge.escrows[1] / 2,
                0
            ]
        );
    }

    function _challengerWin(Challenge.Data storage challenge) private {
        IVMTracker(challenge.vmAddress).completeChallenge(
            challenge.players,
            [
                0,
                challenge.escrows[1] + challenge.escrows[0] / 2
            ]
        );
    }
}
