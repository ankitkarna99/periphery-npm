const chalk = require('chalk')
const { ethers } = require('hardhat')
const { boundaries } = require('../../util/boundaries')
const { generateTree, parseLeaf } = require('../../util/tree')
const { deployUpgradeable, deployProtocol } = require('../../util/factory')
const { getDemoLeaves, getDemoLeavesRaw } = require('../../util/demo-leaves')
const helper = require('../../util/helper')

const PERSONAS = {
  0: 'N/A',
  1: 'Guardian',
  2: 'Beast'
}

describe('Merkle Proof Validation', () => {
  let minter, nft, contracts

  before(async () => {
    const [owner] = await ethers.getSigners()
    contracts = await deployProtocol(owner)

    nft = await deployUpgradeable('FakeNeptuneLegends', 'https://neptunemutual.com', owner.address, owner.address)
    minter = await deployUpgradeable('MerkleProofMinter', nft.address, owner.address, owner.address)

    await minter.grantRole(ethers.utils.formatBytes32String('proof:agent'), owner.address)
    await minter.setBoundaries(...boundaries)
  })

  it('must correctly accept proofs for minting', async () => {
    const signers = await ethers.getSigners()
    let lastBoundTokenId = 1000
    const ppm = await deployUpgradeable('PolicyProofMinter', contracts.store.address, nft.address, 1, 10000)
    const leaves = getDemoLeaves(signers)
    const tree = generateTree(leaves)
    const root = tree.getHexRoot()
    await minter.setMerkleRoot(root)

    const rawLeaves = getDemoLeavesRaw(signers)
    const candidates = {}
    const boundTokens = {}
    const mintedTokens = {}

    for (const [account, level, , persona] of rawLeaves) {
      candidates[account.address] = candidates[account.address] || {
        account: account,
        personas: {}
      }

      candidates[account.address].personas[level] = persona
    }

    for (const key in candidates) {
      const candidate = candidates[key]
      const personas = Object.values(candidate.personas)
        .concat([...Array(7)].fill(1))
        .filter((_, index) => index % 2 === 0)
        .slice(0, 3)

      await minter.connect(candidate.account).setMyPersona(personas)
      lastBoundTokenId++

      if (!boundTokens[key]) {
        await contracts.cxToken.mint(candidate.account.address, helper.ether(1))
        await ppm.connect(candidate.account).mint(contracts.cxToken.address, lastBoundTokenId)
        boundTokens[key] = lastBoundTokenId
      }
    }

    for (const leaf of rawLeaves) {
      const proof = tree.getHexProof(parseLeaf(leaf))
      const [account, level, family, persona] = leaf
      const familyFormatted = ethers.utils.formatBytes32String(family)
      const boundary = boundaries[2].find(item => item.family === familyFormatted && item.level === level)

      if (!mintedTokens[level + family]) {
        mintedTokens[level + family] = boundary.min
      }

      mintedTokens[level + family] += 1
      const tokenId = mintedTokens[level + family]

      await minter.connect(account).mint(proof, boundTokens[account.address], level, familyFormatted, persona, tokenId)

      await minter.connect(account).mint(proof, boundTokens[account.address], level, familyFormatted, persona, tokenId + 1)
        .should.be.rejectedWith('TokenAlreadyClaimedError')

      console.log('%s- %s Level %s Token Id: %s %s (%s)', ' '.repeat(4), chalk.green('[OK]'), level, tokenId, family, PERSONAS[persona])
    }
  })
})
