import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { useToast } from '../components/common/Toast/ToastContext'
import { isValidEmail } from '../utils/validation'
import styles from './AuthPage.module.css'

export default function LoginPage() {
  const { login }  = useAuth()
  const navigate   = useNavigate()
  const toast      = useToast()
  const [form, setForm] = useState({ email: '', password: '', totpCode: '' })
  const [loading, setLoading]   = useState(false)
  const [needMfa, setNeedMfa]   = useState(false)

  const handleChange = (e) => setForm((f) => ({ ...f, [e.target.name]: e.target.value }))

  const handleSubmit = async (e) => {
    e.preventDefault()

    if (!needMfa) {
      if (!isValidEmail(form.email)) {
        return toast('Please enter a valid email address', 'warning')
      }
      if (!form.password) {
        return toast('Please enter your password', 'warning')
      }
    } else {
      if (form.totpCode.length !== 6) {
        return toast('Please enter the 6-digit code', 'warning')
      }
    }

    setLoading(true)
    try {
      const result = await login({
        email:    form.email,
        password: form.password,
        totpCode: needMfa ? form.totpCode : undefined,
      })
      if (result.mfaRequired) {
        setNeedMfa(true)
        toast('Enter your authentication code', 'info')
        return
      }
      if (result.success) {
        navigate('/')
      }
    } catch (err) {
      toast(err.message || 'Login failed', 'error')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.card}>
        <div className={styles.header}>
          <h1 className={styles.title}>Sign in</h1>
          <p className={styles.subtitle}>Book reserved seats on the Colombo Fort – Badulla line</p>
        </div>

        <form onSubmit={handleSubmit} noValidate>
          {!needMfa ? (
            <>
              <div className={styles.field}>
                <label className={styles.label} htmlFor="email">Email address</label>
                <input id="email" name="email" type="email" className={styles.input}
                  value={form.email} onChange={handleChange} required autoComplete="email" />
              </div>
              <div className={styles.field}>
                <label className={styles.label} htmlFor="password">Password</label>
                <input id="password" name="password" type="password" className={styles.input}
                  value={form.password} onChange={handleChange} required autoComplete="current-password" />
              </div>
            </>
          ) : (
            <div className={styles.mfaBox}>
              <p className={styles.mfaHint}>
                Enter the 6-digit code from your authenticator app.
              </p>
              <input
                id="totpCode"
                name="totpCode"
                type="text"
                inputMode="numeric"
                pattern="[0-9]{6}"
                maxLength={6}
                className={`${styles.input} ${styles.totpInput}`}
                value={form.totpCode}
                onChange={handleChange}
                placeholder="000000"
                autoFocus
              />
            </div>
          )}

          <button type="submit" className={styles.submitBtn} disabled={loading} id="login-btn">
            {loading ? 'Signing in…' : needMfa ? 'Verify code' : 'Sign in'}
          </button>
        </form>

        {!needMfa && (
          <p className={styles.footer}>
            Don't have an account? <Link to="/register">Register</Link>
          </p>
        )}
        {needMfa && (
          <button className={styles.backLink} onClick={() => setNeedMfa(false)}>
            ← Back to login
          </button>
        )}
      </div>
    </div>
  )
}
