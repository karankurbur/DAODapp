const { expect } = require("chai");
const { ethers } = require("hardhat");
const Web3 = require("web3");

const web3 = new Web3();

const {
  signTypedData,
  SignTypedDataVersion,
} = require("@metamask/eth-sig-util");

describe("DAO", function () {
  let contract;
  let nftContract;
  const chainId = 31337;
  const privateKey =
    "0x031900399dfbaa2b4d69ab4709799788537617ab75e5adc773866e43353f285b";
  const publicAddress = "0x53f45baddecf731D06439063913FC60331EE1b8c";

  let acc1;
  let acc2;
  let acc3;
  let acc4;
  let wallet;
  const resetContract = async () => {
    [acc1, acc2, acc3, acc4, acc5] = await ethers.getSigners();

    wallet = new ethers.Wallet(privateKey, ethers.provider);

    const NFTMarketPlace = await ethers.getContractFactory(
      "FakeNftMarketplace"
    );
    const nFTMarketPlace = await NFTMarketPlace.deploy();
    await nFTMarketPlace.deployed();
    nftContract = nFTMarketPlace;

    const DAO = await ethers.getContractFactory("DAO");
    const dao = await DAO.deploy(chainId);
    await dao.deployed();
    contract = dao;
    await acc1.sendTransaction({
      to: publicAddress,
      value: ethers.utils.parseEther("5"),
    });

    await contract.purchaseMembership({ value: ethers.utils.parseUnits("1") });
    await contract
      .connect(acc2)
      .purchaseMembership({ value: ethers.utils.parseUnits("1") });
    await contract
      .connect(acc3)
      .purchaseMembership({ value: ethers.utils.parseUnits("1") });
    await contract
      .connect(acc4)
      .purchaseMembership({ value: ethers.utils.parseUnits("1") });
    await contract
      .connect(wallet)
      .purchaseMembership({ value: ethers.utils.parseUnits("1") });

    const buyNFTCallData = web3.eth.abi.encodeFunctionCall(
      {
        inputs: [
          {
            internalType: "address",
            name: "nftMarketplace",
            type: "address",
          },
          {
            internalType: "uint256",
            name: "nftId",
            type: "uint256",
          },
        ],
        name: "buyNFT",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
      },
      [nftContract.address, 5]
    );

    await contract.createProposal([contract.address], [0], [buyNFTCallData]);
    expect(await contract.getRecentProposalId()).to.equal(1);
  };

  describe("Vote", function () {
    beforeEach(async function () {
      await resetContract();
    });

    it("Should execute a passed proposal", async function () {
      await contract.castVote(1, true);
      await contract.connect(acc2).castVote(1, true);
      await contract.executeProposal(1);

      const proposal = await contract.proposals(1);
      expect(proposal.executed).to.equal(true);
    });

    it("Should cast a 'FOR' vote using signature", async function () {
      const message = {
        proposalId: 1,
        vote: true,
      };

      const typedData = {
        types: {
          EIP712Domain: [
            { name: "name", type: "string" },
            { name: "chainId", type: "uint256" },
            { name: "verifyingContract", type: "address" },
          ],
          Vote: [
            { name: "proposalId", type: "uint" },
            { name: "vote", type: "bool" },
          ],
        },
        primaryType: "Vote",
        domain: {
          name: "DAO",
          chainId,
          verifyingContract: contract.address,
        },
        message,
      };

      const sig = signTypedData({
        data: typedData,
        /** .slice(2) removes '0x'
         * signTypedData() expectes just the private key
         * */
        privateKey: Buffer.from(wallet.privateKey.slice(2), "hex"),
        version: SignTypedDataVersion.V4,
      });

      const { v, r, s } = ethers.utils.splitSignature(sig);

      await contract.castVoteWithSignatureBulk([1], [true], [v], [r], [s]);

      expect(await contract.getProposalVotes(1)).to.equal(1);
    });
  });
});
