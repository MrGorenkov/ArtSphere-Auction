import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano } from '@ton/core';
import { ArtSphereCollection } from '../build/ArtSphereCollection/ArtSphereCollection_ArtSphereCollection';
import '@ton/test-utils';

describe('ArtSphereCollection', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let artSphereCollection: SandboxContract<ArtSphereCollection>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        artSphereCollection = blockchain.openContract(await ArtSphereCollection.fromInit());

        deployer = await blockchain.treasury('deployer');

        const deployResult = await artSphereCollection.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            null,
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: artSphereCollection.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and artSphereCollection are ready to use
    });
});
