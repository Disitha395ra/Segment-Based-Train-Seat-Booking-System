import { useState } from 'react'
import { authApi } from '../api/endpoints'
import { useToast } from '../components/common/Toast/ToastContext'
import styles from './AuthPage.module.css'

export default function MfaPage() {
  const toast = useToast()
  const [setup,   setSetup]   = useState(null)
  const [code,    setCode]    = useState('')
  const [loading, setLoading] = useState(false)
  const [step,    setStep]    = useState('init') // init | setup | done

  const handleSetup = async () => {
    setLoading(true)
    try {
      const res = await authApi.mfaSetup()
      setSetup(res.data)
      setStep('setup')
    } catch (err) {
      toast(err.message || 'MFA setup failed', 'error')
    } finally {
      setLoading(false)
    }
  }

  const handleVerify = async (e) => {
    e.preventDefault()
    setLoading(true)
    try {
      await authApi.mfaVerify(code)
      toast('MFA enabled successfully!', 'success')
      setStep('done')
    } catch (err) {
      toast(err.message || 'Invalid code', 'error')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.card}>
        <div className={styles.header}>
          <h1 className={styles.title}>Two-factor authentication</h1>
          <p className={styles.subtitle}>Protect your account with an authenticator app</p>
        </div>

        {step === 'init' && (
          <>
            <p style={{ fontSize: 'var(--font-size-sm)', color: 'var(--color-neutral-600)', marginBottom: 'var(--space-6)', lineHeight: 'var(--line-height-relaxed)' }}>
              Set up two-factor authentication (2FA) using an app like Google Authenticator, Authy, or any TOTP-compatible app.
            </p>
            <button className={styles.submitBtn} onClick={handleSetup} disabled={loading}>
              {loading ? 'Generating…' : 'Set up 2FA'}
            </button>
          </>
        )}

        {step === 'setup' && setup && (
          <>
            <div style={{ textAlign: 'center', marginBottom: 'var(--space-6)' }}>
              <p style={{ fontSize: 'var(--font-size-sm)', color: 'var(--color-neutral-600)', marginBottom: 'var(--space-4)' }}>
                Scan this QR code in your authenticator app, then enter the 6-digit code to verify.
              </p>
              {/* QR code displayed as URI text — in production, render as actual QR image */}
              <div style={{ background: 'var(--color-neutral-100)', borderRadius: 'var(--radius-md)',
                            padding: 'var(--space-4)', wordBreak: 'break-all',
                            fontFamily: 'monospace', fontSize: 'var(--font-size-xs)',
                            color: 'var(--color-neutral-700)', marginBottom: 'var(--space-4)' }}>
                <strong>Secret:</strong> {setup.secret}
              </div>
              <p style={{ fontSize: 'var(--font-size-xs)', color: 'var(--color-neutral-400)', marginBottom: 'var(--space-2)' }}>
                Or enter this URI in your app:
              </p>
              <code style={{ fontSize: 'var(--font-size-xs)', wordBreak: 'break-all',
                             color: 'var(--color-primary-700)' }}>
                {setup.qrUri}
              </code>
            </div>

            {setup.backupCodes && (
              <div style={{ background: 'var(--color-accent-50)', border: '1px solid var(--color-accent-100)',
                            borderRadius: 'var(--radius-md)', padding: 'var(--space-4)',
                            marginBottom: 'var(--space-6)' }}>
                <p style={{ fontSize: 'var(--font-size-xs)', fontWeight: 'var(--font-weight-semibold)',
                             color: 'var(--color-accent-700)', marginBottom: 'var(--space-2)' }}>
                  Save these backup codes (shown only once):
                </p>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-1)' }}>
                  {setup.backupCodes.map((c) => (
                    <code key={c} style={{ fontSize: 'var(--font-size-xs)', color: 'var(--color-neutral-700)' }}>
                      {c}
                    </code>
                  ))}
                </div>
              </div>
            )}

            <form onSubmit={handleVerify}>
              <div className={styles.mfaBox}>
                <p className={styles.mfaHint}>Enter the code from your authenticator app</p>
                <input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]{6}"
                  maxLength={6}
                  className={`${styles.input} ${styles.totpInput}`}
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  placeholder="000000"
                  required
                />
              </div>
              <button type="submit" className={styles.submitBtn} disabled={loading}>
                {loading ? 'Verifying…' : 'Enable 2FA'}
              </button>
            </form>
          </>
        )}

        {step === 'done' && (
          <div style={{ textAlign: 'center' }}>
            <div className={styles.mfaBox} style={{ background: 'var(--color-success-50)', border: '1.5px solid var(--color-success-600)' }}>
              <p style={{ color: 'var(--color-success-700)', fontWeight: 'var(--font-weight-semibold)' }}>
                ✓ Two-factor authentication is now active on your account.
              </p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
