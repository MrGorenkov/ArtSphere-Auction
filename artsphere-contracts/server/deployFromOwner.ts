/// Standalone deploy: разворачивает контракт ArtSphereCollection в TON Testnet
/// от имени owner-кошелька (mnemonic в OWNER_MNEMONIC). Возвращает адрес контракта.
///
/// Запуск: `OWNER_MNEMONIC="..." npx ts-node server/deployFromOwner.ts`
/// Вывод: одна строка с адресом коллекции в form `EQ...`

import { TonClient, WalletContractV4, internal } from '@ton/ton';
import { mnemonicToPrivateKey } from '@ton/crypto';
import { toNano } from '@ton/core';
import { ArtSphereCollection } from '../build/ArtSphereCollection/ArtSphereCollection_ArtSphereCollection';

const ENDPOINT = 'https://testnet.toncenter.com/api/v2/jsonRPC';
const POLL_INTERVAL_MS = 5_000;
const POLL_TIMEOUT_MS = 180_000;
// Без API-ключа Toncenter ограничивает ~1 req/sec — выдерживаем 1.5 сек между всеми вызовами.
const ANONYMOUS_THROTTLE_MS = 1_500;

const log = (...args: unknown[]) => console.error('[deploy]', ...args);

async function sleep(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

/// Обёртка для retry на 429.
async function withRetry<T>(label: string, fn: () => Promise<T>, attempts = 5): Promise<T> {
    for (let i = 0; i < attempts; i++) {
        try {
            return await fn();
        } catch (e: unknown) {
            const msg = String((e as Error)?.message ?? e);
            if (msg.includes('429') || msg.toLowerCase().includes('ratelimit')) {
                const wait = ANONYMOUS_THROTTLE_MS * (i + 2);
                log(`${label}: rate-limited, retry in ${wait}ms (attempt ${i + 1}/${attempts})`);
                await sleep(wait);
                continue;
            }
            throw e;
        }
    }
    throw new Error(`${label}: exceeded retries`);
}

async function main() {
    const mnemonic = process.env.OWNER_MNEMONIC;
    if (!mnemonic) {
        console.error('OWNER_MNEMONIC env is required');
        process.exit(2);
    }
    const apiKey = process.env.TONCENTER_API_KEY;

    // Toncenter v2 принимает ключ только через query-param (header X-API-Key игнорируется
    // на новых ключах), поэтому подшиваем его прямо в URL endpoint.
    const endpoint = apiKey ? `${ENDPOINT}?api_key=${apiKey}` : ENDPOINT;
    const client = new TonClient({ endpoint });
    const key = await mnemonicToPrivateKey(mnemonic.trim().split(/\s+/));
    const wallet = WalletContractV4.create({ workchain: 0, publicKey: key.publicKey });
    const ownerContract = client.open(wallet);

    log('owner:', wallet.address.toString({ testOnly: true }));

    // 1. Init контракта от текущего owner — детерминированно вычисляет адрес.
    const collection = await ArtSphereCollection.fromInit(wallet.address);
    const collectionAddress = collection.address;
    log('computed collection address:', collectionAddress.toString({ testOnly: true }));

    // 2. Проверяем — может уже задеплоен
    await sleep(ANONYMOUS_THROTTLE_MS);
    const stateBefore = await withRetry('getContractState', () => client.getContractState(collectionAddress));
    if (stateBefore.state === 'active') {
        log('already deployed and active');
        process.stdout.write(collectionAddress.toString({ testOnly: true }));
        return;
    }

    // 3. Отправляем Deploy. opened.send() внутри сделает несколько запросов
    //    (getSeqno, send external) — добавляем throttle перед ним.
    await sleep(ANONYMOUS_THROTTLE_MS);
    const opened = client.open(collection);
    await withRetry('opened.send', () => opened.send(
        ownerContract.sender(key.secretKey),
        { value: toNano('0.1') },
        { $$type: 'Deploy', queryId: 0n }
    ));
    log('deploy message sent, waiting for activation…');

    // 4. Ждём пока состояние станет active
    const deadline = Date.now() + POLL_TIMEOUT_MS;
    while (Date.now() < deadline) {
        await sleep(POLL_INTERVAL_MS);
        try {
            const state = await withRetry('poll', () => client.getContractState(collectionAddress));
            log('state:', state.state);
            if (state.state === 'active') {
                process.stdout.write(collectionAddress.toString({ testOnly: true }));
                return;
            }
        } catch (e) {
            log('poll error:', (e as Error).message);
        }
    }

    console.error('Timeout: контракт не активировался за', POLL_TIMEOUT_MS, 'ms');
    process.exit(3);
}

main().catch((err) => {
    console.error('Deploy failed:', err);
    process.exit(1);
});
