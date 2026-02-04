import { createContext, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import * as linera from '@linera/client';
import { Wallet } from 'ethers';

const LineraContext = createContext();

const DEFAULT_FAUCET_URL =
  typeof import.meta !== 'undefined' && import.meta.env?.VITE_LINERA_FAUCET_URL
    ? import.meta.env.VITE_LINERA_FAUCET_URL
    : 'http://localhost:8080';

const DEFAULT_APPLICATION_ID =
  typeof import.meta !== 'undefined' && import.meta.env?.VITE_LINERA_APPLICATION_ID
    ? import.meta.env.VITE_LINERA_APPLICATION_ID
    : '';

const syncHeightCookieName = (chainId) => `linera_sync_height_${String(chainId || '')}`;
const syncHeightStorageKey = (chainId) => `linera_sync_height:${String(chainId || '')}`;

const parseHeightNumber = (value) => {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.floor(value);
  if (typeof value === 'string') {
    const n = Number.parseInt(value, 10);
    return Number.isFinite(n) ? n : null;
  }
  return null;
};

const extractNotificationHeight = (notification) => {
  const direct =
    parseHeightNumber(notification?.height) ??
    parseHeightNumber(notification?.blockHeight) ??
    parseHeightNumber(notification?.block_height);
  if (direct != null) return direct;
  const nb = notification?.reason?.NewBlock;
  const newBlock =
    parseHeightNumber(nb) ??
    parseHeightNumber(nb?.height) ??
    parseHeightNumber(nb?.blockHeight) ??
    parseHeightNumber(nb?.block_height);
  if (newBlock != null) return newBlock;
  try {
    const s = JSON.stringify(notification);
    const m =
      s.match(/block_height"?\s*[:=]\s*"?(\d+)"?/i) ||
      s.match(/blockHeight"?\s*[:=]\s*"?(\d+)"?/i) ||
      s.match(/height"?\s*[:=]\s*"?(\d+)"?/i);
    if (m?.[1]) {
      const n = Number.parseInt(m[1], 10);
      return Number.isFinite(n) ? n : null;
    }
  } catch {}
  return null;
};

const ensureWasmInstantiateStreamingFallback = () => {
  if (typeof WebAssembly === 'undefined') return;
  const wasmAny = WebAssembly;
  const original = wasmAny.instantiateStreaming;
  if (typeof original !== 'function') return;
  wasmAny.instantiateStreaming = async (source, importObject) => {
    try {
      const res = source instanceof Response ? source : await source;
      const ct = res.headers?.get('Content-Type') || '';
      if (ct.includes('application/wasm')) {
        return original(Promise.resolve(res), importObject);
      }
      const buf = await res.arrayBuffer();
      return WebAssembly.instantiate(buf, importObject);
    } catch {
      const res = source instanceof Response ? source : await source;
      const buf = await res.arrayBuffer();
      return WebAssembly.instantiate(buf, importObject);
    }
  };
};

const escapeGqlString = (value) =>
  String(value)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\r/g, '\\r')
    .replace(/\n/g, '\\n');

/** Linera expects chain/application IDs as hex (and optional ':'). Strip hyphens, spaces, etc. */
const normalizeLineraId = (id) => {
  if (id == null || typeof id !== 'string') return '';
  return String(id).replace(/[^0-9a-fA-F:]/g, '');
};

const defaultPlayerName = (chainId) => {
  if (!chainId) return 'Player';
  return `Player-${String(chainId).slice(0, 6)}`;
};

export const LineraContextProvider = ({ children }) => {
  const [ready, setReady] = useState(false);
  const [initError, setInitError] = useState('');
  const [initStage, setInitStage] = useState('');
  const [chainId, setChainId] = useState('');
  const [applicationId, setApplicationId] = useState(DEFAULT_APPLICATION_ID);
  const [faucetUrl, setFaucetUrl] = useState(DEFAULT_FAUCET_URL);
  const [syncHeight, setSyncHeight] = useState(null);
  const [syncUnlocked, setSyncUnlocked] = useState(true);

  const [game, setGame] = useState(null);
  const [matchStatus, setMatchStatus] = useState(null);
  const [isHost, setIsHost] = useState(false);
  const [opponentChainId, setOpponentChainId] = useState(null);
  const [board, setBoard] = useState([]);
  const [currentTurnChainId, setCurrentTurnChainId] = useState(null);
  const [winnerChainId, setWinnerChainId] = useState(null);
  const [lastNotification, setLastNotification] = useState(null);

  const clientRef = useRef(null);
  const chainRef = useRef(null);
  const appRef = useRef(null);
  const notificationUnsubRef = useRef(null);
  const refreshInFlightRef = useRef(false);
  const syncMinHeightRef = useRef(0);
  const refreshDebounceTimerRef = useRef(null);
  const lastSnapshotRef = useRef({});
  const initInProgressRef = useRef(false);
  const isMountedRef = useRef(true);

  const gql = useCallback(async (queryOrMutation) => {
    if (!appRef.current) throw new Error('Linera app not initialized');
    const res = await appRef.current.query(JSON.stringify({ query: queryOrMutation }));
    const data = typeof res === 'string' ? JSON.parse(res) : res;
    if (data?.errors?.length) {
      const msg = data.errors.map((e) => e.message).join('; ');
      throw new Error(msg);
    }
    return data?.data;
  }, []);

  const refresh = useCallback(async () => {
    if (!ready) return;
    if (!syncUnlocked) {
      setGame(null);
      setMatchStatus(null);
      setIsHost(false);
      setOpponentChainId(null);
      setBoard([]);
      setCurrentTurnChainId(null);
      setWinnerChainId(null);
      return;
    }
    if (refreshInFlightRef.current) return;
    refreshInFlightRef.current = true;
    try {
      const data = await gql(`
        query {
          game {
            matchId
            hostChainId
            status
            players { chainId name }
            board
            currentTurnIndex
            winnerChainId
          }
          matchStatus
          isHost
          opponentChainId
          board
          currentTurnChainId
          winnerChainId
          lastNotification
        }
      `);
      const nextGame = data?.game ?? null;
      const nextGameJson = JSON.stringify(nextGame);
      if (nextGameJson !== lastSnapshotRef.current.gameJson) {
        lastSnapshotRef.current.gameJson = nextGameJson;
        setGame(nextGame);
      }

      setMatchStatus((prev) => (prev === (data?.matchStatus ?? null) ? prev : (data?.matchStatus ?? null)));
      setIsHost((prev) => (prev === Boolean(data?.isHost) ? prev : Boolean(data?.isHost)));
      setOpponentChainId((prev) => (prev === (data?.opponentChainId ?? null) ? prev : (data?.opponentChainId ?? null)));

      const nextBoard = Array.isArray(data?.board) ? data.board : (nextGame?.board ?? []);
      setBoard((prev) => (JSON.stringify(prev) === JSON.stringify(nextBoard) ? prev : nextBoard));

      setCurrentTurnChainId((prev) => (prev === (data?.currentTurnChainId ?? null) ? prev : (data?.currentTurnChainId ?? null)));
      setWinnerChainId((prev) => (prev === (data?.winnerChainId ?? null) ? prev : (data?.winnerChainId ?? null)));
      setLastNotification((prev) => (prev === (data?.lastNotification ?? null) ? prev : (data?.lastNotification ?? null)));
    } catch (e) {
      setLastNotification(String(e?.message || e));
    } finally {
      refreshInFlightRef.current = false;
    }
  }, [gql, ready, syncUnlocked]);

  const scheduleRefresh = useCallback(() => {
    if (refreshDebounceTimerRef.current) return;
    refreshDebounceTimerRef.current = setTimeout(() => {
      refreshDebounceTimerRef.current = null;
      refresh();
    }, 150);
  }, [refresh]);

  const startNotifications = useCallback(() => {
    if (!isMountedRef.current) return;
    if (!chainRef.current || typeof chainRef.current.onNotification !== 'function') return;
    if (typeof notificationUnsubRef.current === 'function') {
      try {
        notificationUnsubRef.current();
      } catch {}
      notificationUnsubRef.current = null;
    }
    const handler = (notification) => {
      try {
        const height = extractNotificationHeight(notification);
        if (height != null && chainId) {
          const storageKey = syncHeightStorageKey(chainId);
          const nextStoredHeight = Math.max(syncMinHeightRef.current || 0, height);
          syncMinHeightRef.current = nextStoredHeight;
          setSyncHeight((prev) => (prev === nextStoredHeight ? prev : nextStoredHeight));
          try {
            localStorage.setItem(storageKey, String(nextStoredHeight));
          } catch {}
          if (height >= (syncMinHeightRef.current || 0)) {
            setSyncUnlocked(true);
          }
        }
        if (notification?.reason?.NewBlock && syncUnlocked) {
          scheduleRefresh();
        } else if (notification?.reason?.NewBlock && !syncUnlocked) {
          const heightNow = extractNotificationHeight(notification);
          if (heightNow != null && heightNow >= (syncMinHeightRef.current || 0)) {
            setSyncUnlocked(true);
            scheduleRefresh();
          }
        }
      } catch {}
    };
    const maybeUnsub = chainRef.current.onNotification(handler);
    if (typeof maybeUnsub === 'function') {
      notificationUnsubRef.current = maybeUnsub;
    }
  }, [chainId, scheduleRefresh, syncUnlocked]);

  const initLinera = useCallback(async () => {
    // Prevent concurrent initialization
    if (initInProgressRef.current) return;
    initInProgressRef.current = true;

    try {
      setInitError('');
      setInitStage('Initializing wallet...');
      setReady(false);
      setSyncHeight(null);
      setSyncUnlocked(true);
      setGame(null);
      setLastNotification(null);

      const normalizedAppIdFromEnv = normalizeLineraId(applicationId);
      if (!normalizedAppIdFromEnv) {
        setInitError('Missing or invalid VITE_LINERA_APPLICATION_ID (expected hex, may contain colons)');
        setInitStage('Configuration error');
        return;
      }

      ensureWasmInstantiateStreamingFallback();
      setInitStage('Initializing Linera...');
      try {
        await linera.initialize();
        // Small delay to ensure WASM is fully loaded
        await new Promise(resolve => setTimeout(resolve, 100));
      } catch (e) {
        console.warn('Linera initialization warning:', e);
      }

      setInitStage('Preparing mnemonic...');
      let mnemonic = '';
      try {
        mnemonic = localStorage.getItem('linera_mnemonic') || '';
      } catch {}
      if (!mnemonic) {
        const generated = Wallet.createRandom();
        const phrase = generated.mnemonic?.phrase;
        if (!phrase) {
          setInitError('Failed to generate mnemonic');
          setInitStage('Mnemonic generation failed');
          return;
        }
        mnemonic = phrase;
        try {
          localStorage.setItem('linera_mnemonic', mnemonic);
        } catch {}
      }

      try {
        setInitStage('Creating wallet...');
        const signer = linera.signer.PrivateKey.fromMnemonic(mnemonic);
        const faucet = new linera.Faucet(faucetUrl);
        const owner = signer.address();

        const wallet = await faucet.createWallet();
        setInitStage('Creating microchain...');
        const newChainId = await faucet.claimChain(wallet, owner);

        setInitStage('Connecting to application...');
        const clientInstance = await new linera.Client(wallet, signer, { skipProcessInbox: false });
        const chain = await clientInstance.chain(newChainId);
        const application = await chain.application(normalizedAppIdFromEnv);

        clientRef.current = clientInstance;
        chainRef.current = chain;
        appRef.current = application;
        let minHeight = 0;
        try {
          const localValue = localStorage.getItem(syncHeightStorageKey(newChainId)) || '';
          minHeight = parseHeightNumber(localValue) ?? 0;
        } catch {
          minHeight = 0;
        }
        syncMinHeightRef.current = minHeight;
        setSyncUnlocked(minHeight <= 0);
        setChainId(newChainId);
        setReady(true);
        setInitStage('Ready');
      } catch (e) {
        setInitError(String(e?.message ?? e));
        setInitStage('Initialization failed');
        console.error('Linera initialization error:', e);
      }
    } finally {
      initInProgressRef.current = false;
    }
  }, [applicationId, faucetUrl]);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
      if (typeof notificationUnsubRef.current === 'function') {
        try {
          notificationUnsubRef.current();
        } catch {}
        notificationUnsubRef.current = null;
      }
      if (refreshDebounceTimerRef.current) {
        clearTimeout(refreshDebounceTimerRef.current);
        refreshDebounceTimerRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    initLinera();
  }, [initLinera]);

  useEffect(() => {
    if (!ready) return;
    startNotifications();
    if (syncUnlocked) {
      refresh();
    }
    const id = setInterval(() => {
      if (syncUnlocked) refresh();
    }, 2500);
    return () => {
      clearInterval(id);
      if (refreshDebounceTimerRef.current) {
        clearTimeout(refreshDebounceTimerRef.current);
        refreshDebounceTimerRef.current = null;
      }
    };
  }, [ready, refresh, startNotifications, syncUnlocked]);

  const createMatch = useCallback(
    async (hostName) => {
      const name = escapeGqlString(hostName || defaultPlayerName(chainId));
      await gql(`mutation { createMatch(hostName: "${name}") }`);
      await refresh();
    },
    [chainId, gql, refresh]
  );

  const joinMatch = useCallback(
    async (hostChainId, playerName) => {
      const host = escapeGqlString(normalizeLineraId(hostChainId) || hostChainId);
      const name = escapeGqlString(playerName || defaultPlayerName(chainId));
      await gql(`mutation { joinMatch(hostChainId: "${host}", playerName: "${name}") }`);
      await refresh();
    },
    [chainId, gql, refresh]
  );

  const makeMove = useCallback(
    async (row, col) => {
      await gql(`mutation { makeMove(row: ${row}, col: ${col}) }`);
      await refresh();
    },
    [gql, refresh]
  );

  const leaveMatch = useCallback(async () => {
    await gql(`mutation { leaveMatch }`);
    await refresh();
  }, [gql, refresh]);

  const value = useMemo(
    () => ({
      ready,
      initError,
      initStage,
      chainId,
      applicationId,
      faucetUrl,
      syncHeight,
      syncUnlocked,
      game,
      matchStatus,
      isHost,
      opponentChainId,
      board,
      currentTurnChainId,
      winnerChainId,
      lastNotification,
      setApplicationId,
      setFaucetUrl,
      refresh,
      createMatch,
      joinMatch,
      makeMove,
      leaveMatch,
    }),
    [
      applicationId,
      chainId,
      createMatch,
      faucetUrl,
      game,
      initError,
      initStage,
      isHost,
      joinMatch,
      lastNotification,
      matchStatus,
      opponentChainId,
      board,
      currentTurnChainId,
      winnerChainId,
      ready,
      refresh,
      syncHeight,
      syncUnlocked,
      makeMove,
      leaveMatch,
    ]
  );

  return <LineraContext.Provider value={value}>{children}</LineraContext.Provider>;
};

export { LineraContext };
