import styles from './styles.module.css';

/**
 * board: array of 9 numbers, -1 = empty, 0 = X (host), 1 = O (guest)
 * currentTurnChainId: chain ID of player who can move
 * myChainId: current user's chain ID
 * onCellClick(row, col): called when a cell is clicked (only for valid moves)
 */
export default function Board({ board, currentTurnChainId, myChainId, onCellClick }) {
  const isMyTurn = currentTurnChainId === myChainId;
  const safeBoard = Array.isArray(board) && board.length >= 9 ? board : Array(9).fill(-1);

  const handleClick = (row, col) => {
    const idx = row * 3 + col;
    if (safeBoard[idx] >= 0) return;
    if (!isMyTurn) return;
    onCellClick?.(row, col);
  };

  return (
    <div className={styles.wrapper}>
      <div className={styles.grid}>
        {[0, 1, 2].map((row) =>
          [0, 1, 2].map((col) => {
            const idx = row * 3 + col;
            const val = safeBoard[idx];
            const isEmpty = val < 0;
            const canClick = isMyTurn && isEmpty;
            const symbol = val === 0 ? 'X' : val === 1 ? 'O' : '';
            return (
              <button
                key={idx}
                type="button"
                className={`${styles.cell} ${canClick ? styles.cellClickable : ''} ${!isEmpty ? styles.cellFilled : ''}`}
                onClick={() => handleClick(row, col)}
                disabled={!canClick}
              >
                {symbol}
              </button>
            );
          })
        )}
      </div>
    </div>
  );
}
