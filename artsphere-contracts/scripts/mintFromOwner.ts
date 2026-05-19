/// Самостоятельный mint-скрипт, который шлёт MintNFT-сообщение в коллекцию
/// от имени owner-кошелька. Не использует blueprint, чтобы можно было запускать
/// прямо из Vapor через Process(): `npx ts-node scripts/mintFromOwner.ts <artworkId>`.
///
/// Требует env: OWNER_MNEMONIC (24 слова через пробел) и опционально
/// TONCENTER_API_KEY (без него работает с rate-limit).
///
/// Стандартный вывод: одна строка JSON `{"tokenId":"<n>","collection":"<addr>","artworkId":"<id>"}`
/// Любые лог-сообщения пишутся в stderr.

import { TonClient, WalletContractV4, internal } from '@ton/ton';
import { mnemonicToPrivateKey } from '@ton/crypto';
import { Address, beginCell, toNano } from '@ton/core';
import { ArtSphereCollection, storeMintNFT } from '../build/ArtSphereCollection/ArtSphereCollection_ArtSphereCollection';

const COLLECTION_ADDRESS = 'kQAOK4YRtEimfHBDRKeM0DRN_BLTh4GyiyqqaGcHArpCF7Ji';
const ENDPOINT = 'https://testnet.toncenter.com/api/v2/jsonRPC';
const POLL_INTERVAL_MS = 2_000;
const POLL_TIMEOUT_MS = 60_000;

const log = (...args: unknown[]) => console.error('[mint]', ...args);

async function sleep(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readCollectionIndex(client: TonClient, address: Address): Promise<bigint> {
    const contract = client.open(ArtSphereCollection.fromAddress(address));
    return await contract.getGetCollectionData();
}

async function main() {
    const artworkId = process.argv[2];
    if (!artworkId) {
        console.error('Usage: mintFromOwner.ts <artworkId>');
        process.exit(2);
    }

    const mnemonic = process.env.OWNER_MNEMONIC;
    if (!mnemonic) {
        console.error('OWNER_MNEMONIC env is required');
        process.exit(2);
    }
    const apiKey = process.env.TONCENTER_API_KEY;

    const collectionAddress = Address.parse(COLLECTION_ADDRESS);
    const endpoint = apiKey ? `${ENDPOINT}?api_key=${apiKey}` : ENDPOINT;
    const client = new TonClient({ endpoint });

    // 1. Подготовка owner-кошелька из mnemonic
    const key = await mnemonicToPrivateKey(mnemonic.trim().split(/\s+/));
    const wallet = WalletContractV4.create({ workchain: 0, publicKey: key.publicKey });
    const ownerContract = client.open(wallet);
    log('Owner address:', wallet.address.toString({ testOnly: true }));

    // 2. Считываем next_item_index ДО mint
    const indexBefore = await readCollectionIndex(client, collectionAddress);
    log('next_item_index before mint:', indexBefore.toString());

    // 3. Формируем MintNFT message body и шлём transfer от owner-кошелька на коллекцию
    const seqno = await ownerContract.getSeqno();
    const body = beginCell().store(storeMintNFT({ $$type: 'MintNFT', artworkId })).endCell();

    await ownerContract.sendTransfer({
        seqno,
        secretKey: key.secretKey,
        messages: [
            internal({
                to: collectionAddress,
                value: toNano('0.05'),
                bounce: true,
                body,
            }),
        ],
    });
    log('Transfer sent, waiting for next_item_index to update…');

    // 4. Polling: ждём пока контракт обновит счётчик (это и есть подтверждение mint)
    const deadline = Date.now() + POLL_TIMEOUT_MS;
    let indexAfter = indexBefore;
    while (Date.now() < deadline) {
        await sleep(POLL_INTERVAL_MS);
        try {
            indexAfter = await readCollectionIndex(client, collectionAddress);
        } catch (e) {
            log('poll error:', (e as Error).message);
            continue;
        }
        if (indexAfter > indexBefore) {
            log('next_item_index after mint:', indexAfter.toString());
            break;
        }
    }

    if (indexAfter === indexBefore) {
        console.error('Timeout: контракт не инкрементил next_item_index за', POLL_TIMEOUT_MS, 'ms');
        process.exit(3);
    }

    // 5. Возвращаем результат в stdout (одна строка JSON)
    const result = {
        tokenId: indexAfter.toString(),
        collection: COLLECTION_ADDRESS,
        artworkId,
    };
    process.stdout.write(JSON.stringify(result));
}

main().catch((err) => {
    console.error('Mint failed:', err);
    process.exit(1);
});
