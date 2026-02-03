import { useContext } from 'react';
import { useNavigate } from 'react-router-dom';
import { LineraContext } from '../../context/LineraContext';
import Button from '../../components/Button';
import styles from './styles.module.css';

export default function Result() {
  const navigate = useNavigate();
  const { ready, chainId, winnerChainId, leaveMatch } = useContext(LineraContext);

  const hasWinner = Boolean(winnerChainId);
  const isDraw = !hasWinner;
  const didWin = hasWinner && winnerChainId === chainId;

  const handleBackToLobby = async () => {
    try {
      await leaveMatch();
    } finally {
      navigate('/');
    }
  };

  if (!ready) {
    return (
      <div className={styles.container}>
        <p className={styles.message}>Loading...</p>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Game over</h1>
      <p className={styles.message}>
        {didWin ? 'You won!' : isDraw ? "It's a draw!" : 'You lost.'}
      </p>
      <div className={styles.actions}>
        <Button label="Back to lobby" onClick={handleBackToLobby} />
      </div>
    </div>
  );
}
