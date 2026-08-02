import styles from './Toast.module.css'

export default function Toast({ message, type = 'info', onDismiss }) {
  return (
    <div className={`${styles.toast} ${styles[type]}`} role="alert">
      <span className={styles.message}>{message}</span>
      <button className={styles.dismiss} onClick={onDismiss} aria-label="Dismiss">✕</button>
    </div>
  )
}
