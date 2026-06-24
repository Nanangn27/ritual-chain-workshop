// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
    function lockUntil(address) external view returns (uint256);
}

contract AIJudge is PrecompileConsumer {
    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2000;

    uint256 public nextBountyId = 1;

    struct Submission {
        address submitter;
        bytes32 commitment;
        string answer;
        bool revealed;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;

        uint256 submissionDeadline;
        uint256 revealDeadline;

        bool judged;
        bool finalized;

        bytes aiReview;
        uint256 winnerIndex;

        Submission[] submissions;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(address => bool))
        public hasCommitted;

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint256 submissionDeadline,
        uint256 revealDeadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        address indexed submitter
    );

    event AllAnswersJudged(
        uint256 indexed bountyId,
        bytes aiReview
    );

    event WinnerFinalized(
        uint256 indexed bountyId,
        uint256 indexed winnerIndex,
        address indexed winner,
        uint256 reward
    );

    modifier bountyExists(uint256 bountyId) {
        require(
            bounties[bountyId].owner != address(0),
            "bounty not found"
        );
        _;
    }

    modifier onlyOwner(uint256 bountyId) {
        require(
            msg.sender ==
                bounties[bountyId].owner,
            "not bounty owner"
        );
        _;
    }

    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submissionDeadline,
        uint256 revealDeadline
    )
        external
        payable
        returns (uint256 bountyId)
    {
        require(
            msg.value > 0,
            "reward required"
        );

        require(
            submissionDeadline >
                block.timestamp,
            "bad submission deadline"
        );

        require(
            revealDeadline >
                submissionDeadline,
            "bad reveal deadline"
        );

        bountyId = nextBountyId++;

        Bounty storage bounty =
            bounties[bountyId];

        bounty.owner = msg.sender;
        bounty.title = title;
        bounty.rubric = rubric;
        bounty.reward = msg.value;

        bounty.submissionDeadline =
            submissionDeadline;

        bounty.revealDeadline =
            revealDeadline;

        bounty.winnerIndex =
            type(uint256).max;

        emit BountyCreated(
            bountyId,
            msg.sender,
            title,
            msg.value,
            submissionDeadline,
            revealDeadline
        );
    }

    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    )
        external
        bountyExists(bountyId)
    {
        Bounty storage bounty =
            bounties[bountyId];

        require(
            block.timestamp <
                bounty.submissionDeadline,
            "submission closed"
        );

        require(
            !hasCommitted[bountyId][msg.sender],
            "already committed"
        );

        require(
            !bounty.judged,
            "already judged"
        );

        require(
            bounty.submissions.length <
                MAX_SUBMISSIONS,
            "too many submissions"
        );

        bounty.submissions.push(
            Submission({
                submitter: msg.sender,
                commitment: commitment,
                answer: "",
                revealed: false
            })
        );

        hasCommitted[bountyId][msg.sender] =
            true;

        emit CommitmentSubmitted(
            bountyId,
            bounty.submissions.length - 1,
            msg.sender
        );
    }

    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    )
        external
        bountyExists(bountyId)
    {
        Bounty storage bounty =
            bounties[bountyId];

        require(
            block.timestamp >=
                bounty.submissionDeadline,
            "reveal not started"
        );

        require(
            block.timestamp <
                bounty.revealDeadline,
            "reveal closed"
        );

        require(
            bytes(answer).length <=
                MAX_ANSWER_LENGTH,
            "answer too long"
        );

        bytes32 expected =
            keccak256(
                abi.encodePacked(
                    answer,
                    salt,
                    msg.sender,
                    bountyId
                )
            );

        bool found = false;

        for (
            uint256 i = 0;
            i < bounty.submissions.length;
            i++
        ) {
            Submission storage s =
                bounty.submissions[i];

            if (
                s.submitter ==
                    msg.sender &&
                s.commitment ==
                    expected
            ) {
                require(
                    !s.revealed,
                    "already revealed"
                );

                s.answer = answer;
                s.revealed = true;

                found = true;
                break;
            }
        }

        require(
            found,
            "commitment mismatch"
        );

        emit AnswerRevealed(
            bountyId,
            msg.sender
        );
    }

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    )
        external
        bountyExists(bountyId)
        onlyOwner(bountyId)
    {
        Bounty storage bounty =
            bounties[bountyId];

        require(
            block.timestamp >=
                bounty.revealDeadline,
            "reveal phase active"
        );

        require(
            !bounty.judged,
            "already judged"
        );

        uint256 validReveals = 0;

        for (
            uint256 i = 0;
            i < bounty.submissions.length;
            i++
        ) {
            if (
                bounty.submissions[i]
                    .revealed
            ) {
                validReveals++;
            }
        }

        require(
            validReveals > 0,
            "no valid reveals"
        );

        bytes memory output =
            _executePrecompile(
                LLM_INFERENCE_PRECOMPILE,
                llmInput
            );

        (
    bool hasError,
    bytes memory completionData,
    ,
    string memory errorMessage,
    ConvoHistory memory convoHistory
) = abi.decode(
    output,
    (
        bool,
        bytes,
        bytes,
        string,
        ConvoHistory
    )
);

        require(
            !hasError,
            errorMessage
        );

        bounty.judged = true;
        bounty.aiReview =
            completionData;

        emit AllAnswersJudged(
            bountyId,
            completionData
        );
    }

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    )
        external
        bountyExists(bountyId)
        onlyOwner(bountyId)
    {
        Bounty storage bounty =
            bounties[bountyId];

        require(
            bounty.judged,
            "not judged"
        );

        require(
            !bounty.finalized,
            "already finalized"
        );

        require(
            winnerIndex <
                bounty.submissions.length,
            "bad index"
        );

        require(
            bounty
                .submissions[
                    winnerIndex
                ]
                .revealed,
            "winner not revealed"
        );

        bounty.finalized = true;
        bounty.winnerIndex =
            winnerIndex;

        address winner =
            bounty
                .submissions[
                    winnerIndex
                ]
                .submitter;

        uint256 reward =
            bounty.reward;

        bounty.reward = 0;

        (bool ok, ) =
            payable(winner).call{
                value: reward
            }("");

        require(
            ok,
            "payment failed"
        );

        emit WinnerFinalized(
            bountyId,
            winnerIndex,
            winner,
            reward
        );
    }

    function getSubmission(
        uint256 bountyId,
        uint256 index
    )
        external
        view
        returns (
            address submitter,
            bytes32 commitment,
            string memory answer,
            bool revealed
        )
    {
        Submission storage s =
            bounties[bountyId]
                .submissions[index];

        return (
            s.submitter,
            s.commitment,
            s.answer,
            s.revealed
        );
    }
}