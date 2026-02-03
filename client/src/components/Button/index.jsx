import styles from './styles.module.css';

export default function Button({ label, disabled, onClick }) {
  return (
    <button
      type="button"
      className={styles.btn}
      disabled={disabled}
      onClick={onClick}
    >
      {label}
    </button>
  );
}
