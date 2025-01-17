const { ethers } = require('hardhat')
const helper = require('../../util/helper')
const { deployUpgradeable, deployProtocol } = require('../../util/factory')

describe('Soul bound nft mint validation', () => {
  let minter, nft, contracts

  before(async () => {
    const [owner] = await ethers.getSigners()

    nft = await deployUpgradeable('FakeNeptuneLegends', 'https://neptunemutual.com', owner.address, owner.address)
    contracts = await deployProtocol(owner)
    minter = await deployUpgradeable('PolicyProofMinter', contracts.store.address, nft.address, 1, 10000)
  })

  it('must correctly accept proofs for minting', async () => {
    const [owner] = await ethers.getSigners()

    const amounts = [helper.ether(20_000), helper.ether(50_000)]
    await contracts.cxToken.mint(owner.address, amounts[0])

    await minter.mint(contracts.cxToken.address, 50)
  })
})
