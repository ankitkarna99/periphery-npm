const { mine } = require('@nomicfoundation/hardhat-network-helpers')
const factory = require('../../util/factory')
const helper = require('../../util/helper')
const key = require('../../util/key')
const MIN_LOCK_HEIGHT = 10
const PENALTY_RATE = 25n

require('chai')
  .use(require('chai-as-promised'))
  .should()

describe('Vote Escrow Token: unlock', () => {
  let contracts, name, symbol, durations, amounts

  before(async () => {
    name = 'Vote Escrow NPM'
    symbol = 'veNPM'

    const [owner, account1, account2] = await ethers.getSigners()
    contracts = await factory.deployProtocol(owner)
    const veNpm = await factory.deployUpgradeable('VoteEscrowToken', owner.address, contracts.npm.address, owner.address, name, symbol)

    await contracts.store.setBool(key.qualifyMember(veNpm.address), true)

    amounts = [helper.ether(20_000), helper.ether(50_000)]
    durations = [10, 20]

    await contracts.npm.mint(account1.address, amounts[0])
    await contracts.npm.mint(account2.address, amounts[1])

    await contracts.npm.connect(account1).approve(veNpm.address, amounts[0])
    await contracts.npm.connect(account2).approve(veNpm.address, amounts[1])

    await veNpm.connect(account1).lock(amounts[0], durations[0]).should.not.be.rejected
    await veNpm.connect(account2).lock(amounts[1], durations[1]).should.not.be.rejected

    contracts.veNpm = veNpm
    await mine(MIN_LOCK_HEIGHT)
  })

  it('must correctly perform premature unlocks', async () => {
    const signers = await ethers.getSigners()
    let fees = 0n

    for (let i = 0; i < 2; i++) {
      const account = signers[i + 1]

      ;(await contracts.npm.balanceOf(account.address)).should.equal(0)
      ;(await contracts.veNpm._balances(account.address)).should.equal(amounts[i])

      await contracts.veNpm.approve(contracts.veNpm.address, amounts[i])
      await contracts.veNpm.connect(account).unlockPrematurely()

      const balance = await contracts.npm.balanceOf(account.address)
      balance.should.equal((amounts[i] * (100n - PENALTY_RATE)) / 100n)
      fees +=  (amounts[i] * PENALTY_RATE) / 100n
    }

    const [owner] = signers
    ;(await contracts.npm.balanceOf(owner.address)).should.equal(fees)
  })
})
