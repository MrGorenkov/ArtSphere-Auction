import { toNano } from '@ton/core';
// Исправленный точный путь до сгенерированной обертки
import { ArtSphereCollection } from '../build/ArtSphereCollection/ArtSphereCollection_ArtSphereCollection';
import { NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const deployer = provider.sender().address;
    if (!deployer) {
        throw new Error("Sender is undefined. Connect wallet first.");
    }

    const artSphereCollection = provider.open(await ArtSphereCollection.fromInit(deployer));

    await artSphereCollection.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(artSphereCollection.address);

    console.log('====================================================');
    console.log(' КОНТРАКТ УСПЕШНО ЗАДЕПЛОЕН В TESTNET!');
    console.log('Адрес:', artSphereCollection.address.toString());
    console.log('====================================================');
}