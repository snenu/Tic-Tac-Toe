import { useContext, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { LineraContext } from '../../context/LineraContext';
import Button from '../../components/Button';
import styles from './styles.module.css';

const PLAYER_NAME_STORAGE_KEY = 'tictactoe_player_name';

export default function Home() {
  const navigate = useNavigate();
  const { ready, initError, chainId, createMatch } = useContext(LineraContext);
  const [hostChainIdInput, setHostChainIdInput] = useState('');
  const [playerName, setPlayerName] = useState(() => {
    try {
      return localStorage.getItem(PLAYER_NAME_STORAGE_KEY) || '';
    } catch {
      return '';
    }
  });

  const normalizedPlayerName = useMemo(() => String(playerName || '').trim(), [playerName]);
  const normalizedHostChainId = useMemo(() => String(hostChainIdInput || '').trim(), [hostChainIdInput]);

  const canJoin = useMemo(() => {
    if (!ready) return false;
    if (!normalizedHostChainId) return false;
    return true;
  }, [normalizedHostChainId, ready]);

  const canOpenCreate = normalizedPlayerName.length > 0;

  const [copySuccess, setCopySuccess] = useState(false);

  const handleCreateRoom = async () => {
    try {
      await createMatch(normalizedPlayerName);
      navigate(`/room/${chainId}`);
    } catch (error) {
      console.error('Failed to create room:', error);
    }
  };

  const handleJoinRoom = () => {
    if (!canJoin) return;
    const q = normalizedPlayerName ? `?name=${encodeURIComponent(normalizedPlayerName)}` : '';
    navigate(`/room/${normalizedHostChainId}${q}`);
  };

  const handleCopyChainId = async () => {
    try {
      await navigator.clipboard.writeText(chainId);
      setCopySuccess(true);
      setTimeout(() => setCopySuccess(false), 2000);
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  };

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>⭕ Tic-Tac-Toe</h1>
      <p className={styles.subtitle}>🔗 Fully On-Chain · Real-Time · Powered by Linera</p>

      {!ready && (
        <div className={styles.banner}>
          {initError ? (
            <>
              <strong>Error:</strong> {initError}
              {initError.includes('reconnect') && (
                <button
                  type="button"
                  className={styles.refreshButton}
                  onClick={() => window.location.reload()}
                >
                  Refresh page
                </button>
              )}
            </>
          ) : (
            <>
              <span className={styles.spinner}>⏳</span> Initializing Linera blockchain connection...
            </>
          )}
        </div>
      )}

      {ready && (
        <>
          <div className={styles.section}>
            <label className={styles.label}>Your name</label>
            <input
              className={styles.input}
              value={playerName}
              onChange={(e) => {
                const next = e.target.value;
                setPlayerName(next);
                try {
                  localStorage.setItem(PLAYER_NAME_STORAGE_KEY, next);
                } catch {}
              }}
              placeholder="Enter your name"
            />
          </div>

          <div className={styles.section}>
            <h2 className={styles.sectionTitle}>Create room</h2>
            <p className={styles.hint}>Your room ID (share this to play):</p>
            <div className={styles.chainIdBox}>
              <code className={styles.chainId}>{chainId}</code>
              <button
                type="button"
                className={styles.copyBtn}
                onClick={handleCopyChainId}
              >
                {copySuccess ? '✓ Copied!' : 'Copy'}
              </button>
            </div>
            <Button
              label="Create room"
              disabled={!canOpenCreate}
              onClick={handleCreateRoom}
            />
          </div>

          <div className={styles.divider} />

          <div className={styles.section}>
            <h2 className={styles.sectionTitle}>Join room</h2>
            <p className={styles.hint}>Paste the host&apos;s room ID:</p>
            <input
              className={styles.input}
              value={hostChainIdInput}
              onChange={(e) => setHostChainIdInput(e.target.value)}
              placeholder="Host chain ID"
            />
            <Button
              label="Join room"
              disabled={!canJoin}
              onClick={handleJoinRoom}
            />
          </div>
        </>
      )}
    </div>
  );
}
