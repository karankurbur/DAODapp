pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

contract DAO {

    mapping (address => bool) public members;
    mapping (uint => Proposal) public proposals;
    mapping (bytes32 => bool) public previousProposals;
    uint public memberCount;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Vote(uint proposalId,bool vote)");

    uint public chainId;
    uint proposalCount = 0;

    enum ProposalState {       
        Active,
        Succeeded,
        Executed
    }

    struct Proposal {
        uint id;
        address[] targets;
        uint[] values;
        bytes[] calldatas;
        uint nftId;
        bool executed;
        uint votesFor;
        mapping (address => Receipt) votes;
    }

    struct Receipt {
        bool hasVoted;
        bool support;
    }

    constructor(uint _chainId) {
        chainId = _chainId;
    }

    function getQuorum() public view returns (uint) {
        // Need atleast 1 vote to pass
        if(memberCount < 4) {
            return 1;
        }

        return memberCount / 4;
    }

    function getRecentProposalId() public view returns (uint) {
        return proposalCount;
    }

    function getProposalVotes(uint proposalId) public view returns (uint) {
        return proposals[proposalId].votesFor;
    }

    function getProposalState(uint proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        if(proposal.executed) {
            return ProposalState.Executed;
        } else if (proposal.votesFor >= getQuorum()) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Active;
        }
    }

    function createProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas) public {
        bytes32 proposalHash = keccak256(abi.encode(targets, values, calldatas));
        require(!previousProposals[proposalHash], "not unique proposal");
        previousProposals[proposalHash] = true;

        require(members[msg.sender], "not a dao member");
        proposalCount++;
        
        require(targets.length == values.length, "input lengths dont match");
        require(values.length == calldatas.length, "input lengths dont match");

        // Creates a new empty proposal struct
        Proposal storage newProposal = proposals[proposalCount];
        
        // Add information
        newProposal.id = proposalCount;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.calldatas = calldatas;
        newProposal.executed = false;
        newProposal.votesFor = 0;
    }

    function purchaseMembership() public payable {
        require(msg.value == 1 ether, "not 1 eth");
        require(!members[msg.sender], "already member");
        members[msg.sender] = true;
        memberCount++;
    }

    function castVote(uint propsalId, bool vote) public {
        _castVote(msg.sender, propsalId, vote);
    }

    function castVoteWithSignature(uint propsalId, bool vote, uint8 v_, bytes32 r_, bytes32 s_) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("DAO")), chainId, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, propsalId, vote));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v_, r_, s_);

        _castVote(signer, propsalId, vote);
    }

    function _castVote(address sender, uint proposalId, bool vote) internal {
        require(members[sender], "not a dao member");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.votes[sender];
        require(!receipt.hasVoted, "already voted");
        require(getProposalState(proposalId) == ProposalState.Active || getProposalState(proposalId) == ProposalState.Succeeded, "already executed");

        if(vote) {
            proposal.votesFor++;
        }
        receipt.support = vote;
        receipt.hasVoted = true;
    }

    function castVoteWithSignatureBulk(uint[] memory propsalId, bool[] memory vote, uint8[] memory v_, bytes32[] memory r_, bytes32[] memory s_) public {
        require(propsalId.length == vote.length, "input lengths dont match");
        require(vote.length == v_.length, "input lengths dont match");
        require(v_.length == r_.length, "input lengths dont match");
        require(r_.length == s_.length, "input lengths dont match");
        
        for(uint i = 0; i < propsalId.length; i++) {
            castVoteWithSignature(propsalId[i], vote[i], v_[i], r_[i], s_[i]);
        }
    }

    function executeArbitrary(address to, uint amount, bytes memory call) internal returns(bool, bytes memory) {
        (bool success, bytes memory data) = to.call{value: amount}(call);
        return (success, data);
    }

    function sliceUint(bytes memory bs) internal pure returns (uint)
    {
        uint x;
        assembly {
            x := mload(add(bs, 0x20))
        }
        return x;
    }

    function sliceBool(bytes memory bs) internal pure returns (bool)
    {
        bool x;
        assembly {
            x := mload(add(bs, 0x20))
        }
        return x;
    }

    // Common proposal function
    function buyNFT(address nftMarketplace, uint256 nftId) public {
        // Makes this a internal function that can be called using `to`
        require(msg.sender == address(this), "not proposal execution");
        bool success;
        bytes memory returnValue;

        (success, returnValue) = executeArbitrary(nftMarketplace, 0, abi.encodeWithSignature("getPrice(address,uint256)", nftMarketplace, nftId));
        require(success, "getPrice failed");
        uint price = sliceUint(returnValue);

        (success, returnValue) = executeArbitrary(nftMarketplace, price, abi.encodeWithSignature("buy(address,uint256)", nftMarketplace, nftId));
        bool purchaseSuccess = sliceBool(returnValue);
        require(success, "buy nft failed");
        require(purchaseSuccess, "buy nft failed");
    }

    function executeProposal(uint id) public {
        require(members[msg.sender], "not a dao member");

        Proposal storage p = proposals[id];
        require(getProposalState(id) == ProposalState.Succeeded, "not succeeded");

        for(uint i = 0; i < p.targets.length; i++) {
            bool success;
            (success, ) = executeArbitrary(p.targets[i], p.values[i], p.calldatas[i]);
            require(success, "proposal call failed");
        }
        
        p.executed = true;
    }
}

contract FakeNftMarketplace {
    function getPrice(address nftContract, uint nftId) public view returns (uint) {
        return 19038;
    }

    function buy(address nftContract, uint nftId) public payable returns (bool) {
        return true;
    }
}