import { useEffect, useContext, useRef, useState } from 'react';
import { useNavigate, useParams, useLocation } from 'react-router-dom';
import { LineraContext } from '../../context/LineraContext';
import Board from '../../components/Board';
import Button from '../../components/Button';
import styles from './styles.module.css';

const PLAYER_NAME_STORAGE_KEY = 'tictactoe_player_name';

export default function Room() {
  const { id } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const {
    ready,
    initError,
    chainId,
    syncUnlocked,
    game,
    isHost,
    matchStatus,
    board,
    currentTurnChainId,
    winnerChainId,
    lastNotification,
    joinMatch,
    makeMove,
    leaveMatch,
  } = useContext(LineraContext);

  const hasJoinedRef = useRef(false);
  const resultNavTriggeredRef = useRef(false);

  useEffect(() => {
    if (!ready || !syncUnlocked || !id || !chainId || id === chainId) return;
    if (hasJoinedRef.current) return;
    hasJoinedRef.current = true;
    const params = new URLSearchParams(location.search || '');
    let playerName = String(params.get('name') || '').trim();
    if (!playerName) {
      try {
        playerName = String(localStorage.getItem(PLAYER_NAME_STORAGE_KEY) || '').trim();
      } catch {
        playerName = '';
      }
    }
    joinMatch(id, playerName || undefined).catch(() => {
      hasJoinedRef.current = false;
      navigate('/');
    });
  }, [chainId, id, joinMatch, location.search, navigate, ready, syncUnlocked]);

  useEffect(() => {
    if (!ready || id === 'matchmaking' || !syncUnlocked || resultNavTriggeredRef.current) return;
    const status = String(matchStatus || game?.status || '').toLowerCase();
    const ended = status === 'ended' || status === 'draw';
    const hasWinner = Boolean(winnerChainId);
    if (ended || hasWinner) {
      resultNavTriggeredRef.current = true;
      navigate('/result');
    }
  }, [game?.status, id, matchStatus, navigate, ready, syncUnlocked, winnerChainId]);

  const handleCellClick = async (row, col) => {
    if (!ready || !syncUnlocked) return;
    if (gameEnded) return;
    if (currentTurnChainId !== chainId) return;
    try {
      await makeMove(row, col);
    } catch (e) {
      console.error('Failed to make move:', e);
    }
  };

  const handleLeave = async () => {
    try {
      await leaveMatch();
    } finally {
      navigate('/');
    }
  };

  const waitingForOpponent = game?.status === 'WaitingForPlayer';
  const gameEnded = matchStatus === 'Ended' || matchStatus === 'Draw' || winnerChainId;

  if (!ready) {
    return (
      <div className={styles.container}>
        <div className={styles.banner}>
          {initError ? (
            <>
              Error: {initError}
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
            'Initializing Linera...'
          )}
        </div>
      </div>
    );
  }

  if (!syncUnlocked) {
    return (
      <div className={styles.container}>
        <div className={styles.banner}>Syncing chain...</div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Game room</h1>

      {lastNotification && (
        <p className={styles.notification}>{lastNotification}</p>
      )}

      {waitingForOpponent && (
        <p className={styles.waiting}>Waiting for opponent... Share your room ID so they can join.</p>
      )}

      {!waitingForOpponent && game?.players?.length === 2 && (
        <>
          <div className={styles.turnInfo}>
            {currentTurnChainId === chainId ? (
              <span className={styles.myTurn}>Your turn (you are {isHost ? 'X' : 'O'})</span>
            ) : (
              <span className={styles.oppTurn}>Opponent&apos;s turn</span>
            )}
          </div>
          <Board
            board={board}
            currentTurnChainId={currentTurnChainId}
            myChainId={chainId}
            onCellClick={handleCellClick}
          />
        </>
      )}

      {gameEnded && (
        <p className={styles.ended}>
          Game over. {winnerChainId === chainId ? 'You won!' : winnerChainId ? 'You lost.' : "It's a draw!"}
        </p>
      )}

      <div className={styles.actions}>
        <Button label="Leave game" onClick={handleLeave} />
      </div>
    </div>
  );
}
