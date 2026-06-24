Privacy-Preserving AI Bounty Judge

Overview

This homework extends the AI Bounty Judge workshop contract with a commit-reveal workflow that prevents answer copying during the submission phase.

Participants submit commitment hashes instead of plaintext answers. Answers remain hidden until the reveal phase. Only valid revealed answers are eligible for AI judging.

---

New Bounty Lifecycle

1. Create Bounty

The bounty owner creates a bounty with:

- Reward
- Submission deadline
- Reveal deadline
- Evaluation rubric

2. Commit Phase

Participants generate a commitment:

bytes32 commitment =
    keccak256(
        abi.encodePacked(
            answer,
            salt,
            msg.sender,
            bountyId
        )
    );

Only the commitment hash is submitted on-chain.

3. Reveal Phase

After the submission deadline, participants reveal:

- Answer
- Salt

The contract verifies that the reveal matches the original commitment.

4. AI Judging

After the reveal deadline, the bounty owner calls:

judgeAll()

Ritual AI evaluates all revealed submissions together in a single batch request.

5. Winner Selection

The owner reviews the AI output and finalizes one winner.

The reward is paid to the selected submission.

---

Security Improvements

- Prevents answer copying
- Prevents commitment reuse
- Supports fair evaluation
- Requires valid reveals
- Uses batch AI judging
- Maintains human oversight

---

Test Plan

Valid Cases

1. Submit commitment before submission deadline.
2. Reveal answer during reveal phase.
3. Correct salt produces valid reveal.
4. Judge after reveal deadline.
5. Finalize winner after judging.

Invalid Cases

1. Submit after submission deadline.
2. Reveal before reveal phase.
3. Reveal after reveal deadline.
4. Incorrect salt.
5. Incorrect answer.
6. Double commitment from same address.
7. Judge before reveal deadline.
8. Finalize before judging.

---

Architecture Note

Commit-Reveal Model

The required track uses a standard commit-reveal design.

During submission:

- Answers remain hidden.
- Only commitment hashes are visible.

During reveal:

- Participants reveal answers and salts.
- The contract verifies commitments.

Only valid revealed answers are eligible for judging.

Ritual-Native Private Design

A more advanced design would keep answers encrypted until AI judging.

Encrypted submissions could be stored off-chain while only references and hashes are stored on-chain.

A Ritual TEE could privately decrypt submissions and send all answers to the LLM in a single batch request.

The final revealed bundle could be published after judging together with a verification hash.

This approach improves privacy while preserving verifiability.

---

Reflection Question

In a bounty system, information such as rewards, deadlines, rules, and final results should remain public so participants can trust the process. Individual submissions should stay hidden during the submission phase to prevent copying and unfair advantages. Commitment hashes can remain public because they do not reveal the underlying answer. AI should evaluate submissions according to the rubric and provide rankings or recommendations. Humans should remain responsible for defining evaluation criteria, reviewing AI output, and making the final payout decision. This reduces the risk of incorrect or biased AI judgments. Combining hidden submissions, AI-assisted evaluation, and human oversight creates a fair and trustworthy bounty system.

Test Plan

Valid Cases

Test 1 - Valid Commitment

- Create bounty
- Submit commitment before submission deadline
- Expected Result: transaction succeeds

Test 2 - Valid Reveal

- Submit commitment
- Wait until reveal phase
- Reveal correct answer and salt
- Expected Result: reveal succeeds

Test 3 - Valid Judging

- At least one submission successfully revealed
- Wait until reveal deadline
- Call judgeAll()
- Expected Result: AI review stored successfully

Test 4 - Valid Winner Finalization

- judgeAll() completed
- Owner calls finalizeWinner()
- Expected Result: winner receives reward

---

Invalid Cases

Test 5 - Late Commitment

- Submit commitment after submission deadline
- Expected Result: revert with "submission closed"

Test 6 - Early Reveal

- Reveal before submission phase ends
- Expected Result: revert with "reveal not started"

Test 7 - Late Reveal

- Reveal after reveal deadline
- Expected Result: revert with "reveal closed"

Test 8 - Invalid Salt

- Reveal using incorrect salt
- Expected Result: revert with "commitment mismatch"

Test 9 - Invalid Answer

- Reveal using different answer than committed
- Expected Result: revert with "commitment mismatch"

Test 10 - Double Commitment

- Same address submits two commitments
- Expected Result: revert with "already committed"

Test 11 - Judge Too Early

- Call judgeAll() before reveal deadline
- Expected Result: revert with "reveal phase active"

Test 12 - Finalize Before Judging

- Call finalizeWinner() before judgeAll()
- Expected Result: revert with "not judged"