/// Минимальный HTTP-сервис, который шлёт mint-транзакции в коллекцию ArtSphere
/// от имени owner-кошелька. Изолирован от Vapor: api → HTTP POST /mint → ответ.
///
/// Env: OWNER_MNEMONIC (24 слова), опц. TONCENTER_API_KEY, PORT (default 3001).
///
/// Эндпоинты:
///   GET  /health       → {status: 'ok'}
///   POST /mint         body: {artworkId}    →  {tokenId, collection, artworkId}

import * as http from 'http';
import { TonClient, WalletContractV4, internal } from '@ton/ton';
import { mnemonicToPrivateKey } from '@ton/crypto';
import { Address, beginCell, toNano } from '@ton/core';
import { ArtSphereCollection, storeMintNFT } from '../build/ArtSphereCollection/ArtSphereCollection_ArtSphereCollection';

const COLLECTION_ADDRESS = 'kQAOK4YRtEimfHBDRKeM0DRN_BLTh4GyiyqqaGcHArpCF7Ji';
const ENDPOINT = 'https://testnet.toncenter.com/api/v2/jsonRPC';
const PORT = Number(process.env.PORT ?? 3001);
const POLL_INTERVAL_MS = 2_000;
const POLL_TIMEOUT_MS = 60_000;

const log = (...args: unknown[]) => console.log('[minter]', ...args);

function sleep(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readCollectionIndex(client: TonClient, address: Address): Promise<bigint> {
    const contract = client.open(ArtSphereCollection.fromAddress(address));
    return await contract.getGetCollectionData();
}

async function mint(artworkId: string): Promise<{ tokenId: string; collection: string; artworkId: string }> {
    const mnemonic = process.env.OWNER_MNEMONIC;
    if (!mnemonic) throw new Error('OWNER_MNEMONIC env is not set on minter service');
    const apiKey = process.env.TONCENTER_API_KEY;

    const collectionAddress = Address.parse(COLLECTION_ADDRESS);
    // Toncenter v2 принимает ключ только через query-param.
    const endpoint = apiKey ? `${ENDPOINT}?api_key=${apiKey}` : ENDPOINT;
    const client = new TonClient({ endpoint });

    const key = await mnemonicToPrivateKey(mnemonic.trim().split(/\s+/));
    const wallet = WalletContractV4.create({ workchain: 0, publicKey: key.publicKey });
    const ownerContract = client.open(wallet);
    log('owner:', wallet.address.toString({ testOnly: true }), 'artworkId:', artworkId);

    const indexBefore = await readCollectionIndex(client, collectionAddress);
    log('index before:', indexBefore.toString());

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
    log('transfer sent, waiting for state update…');

    const deadline = Date.now() + POLL_TIMEOUT_MS;
    let indexAfter = indexBefore;
    while (Date.now() < deadline) {
        await sleep(POLL_INTERVAL_MS);
        try {
            indexAfter = await readCollectionIndex(client, collectionAddress);
        } catch (e) {
            log('poll error (will retry):', (e as Error).message);
            continue;
        }
        if (indexAfter > indexBefore) {
            log('index after:', indexAfter.toString());
            return { tokenId: indexAfter.toString(), collection: COLLECTION_ADDRESS, artworkId };
        }
    }

    throw new Error(`Timeout: контракт не инкрементил next_item_index за ${POLL_TIMEOUT_MS}ms`);
}

function readBody(req: http.IncomingMessage): Promise<string> {
    return new Promise((resolve, reject) => {
        const chunks: Buffer[] = [];
        req.on('data', (c) => chunks.push(c));
        req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
        req.on('error', reject);
    });
}

const server = http.createServer(async (req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok' }));
        return;
    }

    if (req.method === 'POST' && req.url === '/mint') {
        try {
            const raw = await readBody(req);
            const { artworkId } = JSON.parse(raw || '{}');
            if (!artworkId || typeof artworkId !== 'string') {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'artworkId is required' }));
                return;
            }
            const result = await mint(artworkId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(result));
        } catch (e) {
            log('mint failed:', e);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: (e as Error).message }));
        }
        return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
    log(`minter service listening on :${PORT}`);
});
