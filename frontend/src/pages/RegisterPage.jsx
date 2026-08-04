import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { useToast } from '../components/common/Toast/ToastContext'
import { isValidEmail, isValidName, isValidPassword, isValidPhone } from '../utils/validation'
import styles from './AuthPage.module.css'

export default function RegisterPage() {
  const { register } = useAuth()
  const navigate     = useNavigate()
  const toast        = useToast()
  const [form, setForm] = useState({ fullName: '', email: '', password: '', phone: '' })
  const [loading, setLoading] = useState(false)

  const handleChange = (e) => setForm((f) => ({ ...f, [e.target.name]: e.target.value }))

  const handleSubmit = async (e) => {
    e.preventDefault()
    
    if (!isValidName(form.fullName)) {
      return toast('Please enter a valid full name (min 2 chars)', 'warning')
    }
    if (!isValidEmail(form.email)) {
      return toast('Please enter a valid email address', 'warning')
    }
    if (!isValidPassword(form.password)) {
      return toast('Password must be at least 8 chars, contain an uppercase, a lowercase, and a number', 'warning')
    }
    if (form.phone && !isValidPhone(form.phone)) {
      return toast('Please enter a valid phone number (e.g. 07XXXXXXXX)', 'warning')
    }

    setLoading(true)
    try {
      await register({ fullName: form.fullName, email: form.email,
                       password: form.password, phone: form.phone || undefined })
      toast('Account created! Please sign in.', 'success')
      navigate('/login')
    } catch (err) {
      toast(err.message || 'Registration failed', 'error')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.card}>
        <div className={styles.header}>
          <h1 className={styles.title}>Create account</h1>
          <p className={styles.subtitle}>Join to manage your bookings and view history</p>
        </div>
        <form onSubmit={handleSubmit} noValidate>
          {[
            { id: 'fullName',  label: 'Full name',        type: 'text',     auto: 'name' },
            { id: 'email',     label: 'Email address',    type: 'email',    auto: 'email' },
            { id: 'password',  label: 'Password',         type: 'password', auto: 'new-password',
              hint: 'Min. 8 characters, include uppercase and a number' },
            { id: 'phone',     label: 'Phone (optional)', type: 'tel',      auto: 'tel' },
          ].map(({ id, label, type, auto, hint }) => (
            <div className={styles.field} key={id}>
              <label className={styles.label} htmlFor={id}>{label}</label>
              <input id={id} name={id} type={type} className={styles.input}
                value={form[id]} onChange={handleChange}
                autoComplete={auto} required={id !== 'phone'} />
              {hint && <span className={styles.hint}>{hint}</span>}
            </div>
          ))}
          <button type="submit" className={styles.submitBtn} disabled={loading} id="register-btn">
            {loading ? 'Creating account…' : 'Create account'}
          </button>
        </form>
        <p className={styles.footer}>
          Already have an account? <Link to="/login">Sign in</Link>
        </p>
      </div>
    </div>
  )
}
