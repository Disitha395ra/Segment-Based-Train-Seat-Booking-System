import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { bookingsApi } from '../api/endpoints'
import { useToast } from '../components/common/Toast/ToastContext'
import styles from './PaymentPage.module.css'

export default function PaymentPage() {
  const { state } = useLocation()
  const navigate = useNavigate()
  const toast = useToast()

  const [loading, setLoading] = useState(false)
  const [form, setForm] = useState({
    cardNumber: '',
    expiryDate: '',
    cvc: '',
    cardholderName: ''
  })

  // Prevent accessing payment page directly without state
  if (!state?.booking) {
    navigate('/', { replace: true })
    return null
  }

  const { booking, fare } = state

  const handleChange = (e) => {
    let { name, value } = e.target

    if (name === 'cardNumber') {
      value = value.replace(/\D/g, '').substring(0, 16)
      value = value.replace(/(\d{4})(?=\d)/g, '$1 ') // Add spaces for better formatting
    } else if (name === 'expiryDate') {
      value = value.replace(/\D/g, '').substring(0, 4)
      if (value.length > 2) {
        value = `${value.substring(0, 2)}/${value.substring(2)}`
      }
    } else if (name === 'cvc') {
      value = value.replace(/\D/g, '').substring(0, 3)
    }

    setForm((f) => ({ ...f, [name]: value }))
  }

  const handleSubmit = async (e) => {
    e.preventDefault()

    // Basic validation
    if (form.cardNumber.replace(/\s/g, '').length !== 16) {
      return toast('Invalid card number', 'error')
    }
    if (form.expiryDate.length !== 5) {
      return toast('Invalid expiry date', 'error')
    }
    if (form.cvc.length !== 3) {
      return toast('Invalid CVC', 'error')
    }
    if (!form.cardholderName.trim()) {
      return toast('Cardholder name is required', 'error')
    }

    setLoading(true)
    
    // Simulate payment processing delay (1.5s)
    await new Promise(r => setTimeout(r, 1500))

    try {
      // Actually confirm the booking on backend after mock payment success
      await bookingsApi.confirm(booking.id)
      
      toast('Payment successful!', 'success')
      
      navigate('/confirmation', {
        state: { ...state } // Pass the same state forward to receipt
      })
    } catch (err) {
      toast(err.message || 'Payment processing failed. Please try again.', 'error')
      setLoading(false)
    }
  }

  return (
    <div className={styles.page}>
      <div className="container container--narrow">
        <button className={styles.cancelBtn} onClick={() => navigate(-1)} disabled={loading}>
          Cancel Payment
        </button>

        <div className={styles.paymentContainer}>
          <div className={styles.header}>
            <h1 className={styles.title}>Secure Payment</h1>
            <p className={styles.subtitle}>Complete your payment to confirm the booking</p>
          </div>

          <div className={styles.orderSummary}>
            <div className={styles.summaryItem}>
              <span>Booking Ref:</span>
              <strong>{booking.referenceCode}</strong>
            </div>
            <div className={styles.summaryItem}>
              <span>Total Amount:</span>
              <strong className={styles.amount}>LKR {Number(fare?.totalFare || 0).toFixed(2)}</strong>
            </div>
          </div>

          <form className={styles.form} onSubmit={handleSubmit} noValidate>
            <div className={styles.field}>
              <label htmlFor="cardholderName" className={styles.label}>Cardholder Name</label>
              <input
                id="cardholderName"
                name="cardholderName"
                type="text"
                className={styles.input}
                value={form.cardholderName}
                onChange={handleChange}
                placeholder="Name on card"
                disabled={loading}
              />
            </div>

            <div className={styles.field}>
              <label htmlFor="cardNumber" className={styles.label}>Card Number</label>
              <input
                id="cardNumber"
                name="cardNumber"
                type="text"
                className={styles.input}
                value={form.cardNumber}
                onChange={handleChange}
                placeholder="0000 0000 0000 0000"
                disabled={loading}
              />
            </div>

            <div className={styles.row}>
              <div className={styles.field}>
                <label htmlFor="expiryDate" className={styles.label}>Expiry Date</label>
                <input
                  id="expiryDate"
                  name="expiryDate"
                  type="text"
                  className={styles.input}
                  value={form.expiryDate}
                  onChange={handleChange}
                  placeholder="MM/YY"
                  disabled={loading}
                />
              </div>

              <div className={styles.field}>
                <label htmlFor="cvc" className={styles.label}>CVC</label>
                <input
                  id="cvc"
                  name="cvc"
                  type="password"
                  className={styles.input}
                  value={form.cvc}
                  onChange={handleChange}
                  placeholder="123"
                  disabled={loading}
                />
              </div>
            </div>

            <button type="submit" className={`${styles.payBtn} ${loading ? styles.loadingBtn : ''}`} disabled={loading}>
              {loading ? (
                <>
                  <span className={styles.spinner}></span>
                  Processing Payment...
                </>
              ) : (
                `Pay LKR ${Number(fare?.totalFare || 0).toFixed(2)}`
              )}
            </button>
            <p className={styles.secureNote}>🔒 Payment is securely processed (Mocked)</p>
          </form>
        </div>
      </div>
    </div>
  )
}
