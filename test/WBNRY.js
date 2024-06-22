const { expect } = require('chai');
const { ethers } = require('hardhat');

const tokens = (n) => {
    return ethers.utils.parseUnits(n.toString(), 8);
}

describe('Wrapped BNRY', () => {
    let wrappedBNRY, deployer_owner, user1, user2, user3;

    beforeEach(async () => {
        // Load and deploy WrappedBNRY contract
        const WrappedBNRY = await ethers.getContractFactory('WBNRY');
        wrappedBNRY = await WrappedBNRY.deploy();
        await wrappedBNRY.deployed();

        // Configure accounts
        [deployer_owner, user1, user2, user3] = await ethers.getSigners();
    });

    describe('Deployment', async () => {
        it('Should have the right token name and symbol', async () => {
            expect(await wrappedBNRY.name()).to.equal('Wrapped BNRY');
            expect(await wrappedBNRY.symbol()).to.equal('WBNRY');
        });

        it('Should have the correct owner', async () => {
            expect(await wrappedBNRY.owner()).to.equal(deployer_owner.address);
        });

        it('Should have zero initial supply', async () => {
            expect(await wrappedBNRY.totalSupply()).to.equal(tokens(0));
        });
    });

    describe('Minting', async () => {
        it('Should mint tokens', async () => {
            await wrappedBNRY.mint(user1.address, tokens(1000));
            expect(await wrappedBNRY.balanceOf(user1.address)).to.equal(tokens(1000));
        });

        it('Should not exceed max supply', async () => {
            await expect(wrappedBNRY.mint(user1.address, tokens(120000001))).to.be.revertedWith('WrappedBNRY: Exceeds max supply');
        });
    });

    describe('Minting 2', async () => {
        it('Should mint tokens by owner only', async () => {
            // Owner mints tokens successfully
            await wrappedBNRY.mint(user1.address, tokens(1000));
            expect(await wrappedBNRY.balanceOf(user1.address)).to.equal(tokens(1000));
    
            // Non-owner attempt to mint tokens should fail
            await expect(wrappedBNRY.connect(user1).mint(user1.address, tokens(1000))).to.be.revertedWith('Ownable: caller is not the owner');
        });
    
        it('Should not exceed max supply', async () => {
            await expect(wrappedBNRY.mint(user1.address, tokens(120000001))).to.be.revertedWith('WrappedBNRY: Exceeds max supply');
        });
    });
    

    describe('Burning', async () => {
        it('Should burn tokens', async () => {
            await wrappedBNRY.mint(user1.address, tokens(1000));
            await wrappedBNRY.connect(user1).burn(tokens(500));
            expect(await wrappedBNRY.balanceOf(user1.address)).to.equal(tokens(500));
        });
    });

    describe('Allowance and Approval', async () => {
        it('Should approve and transferFrom', async () => {
            await wrappedBNRY.mint(user1.address, tokens(1000));
            await wrappedBNRY.connect(user1).approve(user2.address, tokens(500));

            expect(await wrappedBNRY.allowance(user1.address, user2.address)).to.equal(tokens(500));

            await wrappedBNRY.connect(user2).transferFrom(user1.address, user3.address, tokens(300));
            expect(await wrappedBNRY.balanceOf(user3.address)).to.equal(tokens(300));
            expect(await wrappedBNRY.allowance(user1.address, user2.address)).to.equal(tokens(200));
        });

        it('Should increase approval', async () => {
            await wrappedBNRY.mint(user1.address, tokens(1000));
            await wrappedBNRY.connect(user1).approve(user2.address, tokens(500));

            await wrappedBNRY.connect(user1).increaseAllowance(user2.address, tokens(200));
            expect(await wrappedBNRY.allowance(user1.address, user2.address)).to.equal(tokens(700));
        });
    });

    describe('Gas Cost', function () {
        it("should measure gas cost of transferFrom", async function () {
            // Mint tokens to the owner's account
            await wrappedBNRY.mint(deployer_owner.address, tokens(100));

            // Approve anotherAccount to spend 10 tokens from owner's account
            const amount = tokens(10);
            await wrappedBNRY.connect(deployer_owner).approve(user1.address, amount);

            const tx = await wrappedBNRY.connect(user1).populateTransaction.transferFrom(deployer_owner.address, user2.address, amount);
            const gasEstimate = await ethers.provider.estimateGas(tx);
            // console.log("Estimated Gas for transferFrom:", gasEstimate.toString());
            expect(gasEstimate).to.be.below(100000);  // Example threshold
        });
    });
});
