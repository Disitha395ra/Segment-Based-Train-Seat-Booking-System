import { useState, useEffect } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { bookingsApi, fareApi } from '../api/endpoints'
import { useAuth } from '../context/AuthContext'
import { useToast } from '../components/common/Toast/ToastContext'
import styles from './BookingPage.module.css'

export default function BookingPage() {
  const { state }  = useLocation()
  const navigate   = useNavigate()
  const { user }   = useAuth()
  const toast      = useToast()

  const [fare,     setFare]     = useState(null)
  const [loading,  setLoading]  = useState(false)
  const [fareLoad, setFareLoad] = useState(true)

  const [form, setForm] = useState({
    passengerName:  user?.fullName  ?? '',
    passengerEmail: user?.email     ?? '',
    passengerPhone: user?.phone     ?? '',
  })

  useEffect(() => {
    if (!state?.seat) { navigate('/', { replace: true }); return }
    fareApi.estimate(
      state.fromStationId, state.toStationId,
      state.seat.coachClass, state.travelDate
    ).then((res) => setFare(res.data))
      .catch(() => {})
      .finally(() => setFareLoad(false))
  }, [state, navigate])

  const handleChange = (e) =>
    setForm((f) => ({ ...f, [e.target.name]: e.target.value }))

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    try {
      const res = await bookingsApi.create({
        seatId:         state.seat.id,
        fromStationId:  state.fromStationId,
        toStationId:    state.toStationId,
        travelDate:     state.travelDate,
        passengerName:  form.passengerName.trim(),
        passengerEmail: form.passengerEmail.trim(),
        passengerPhone: form.passengerPhone.trim() || undefined,
      })
      // Auto-confirm after booking creation
      await bookingsApi.confirm(res.data.id).catch(() => {})
      navigate('/confirmation', {
        state: { booking: res.data, seat: state.seat,
                 fromStationName: state.fromStationName,
                 toStationName:   state.toStationName, fare }
      })
    } catch (err) {
      if (err.code === 'SEAT_CONFLICT') {
        toast('This seat was just booked by another passenger. Please go back and choose another.', 'error', 7000)
      } else {
        toast(err.message || 'Booking failed. Please try again.', 'error')
      }
    } finally {
      setLoading(false)
    }
  }

  if (!state?.seat) return null

  const { seat, fromStationName, toStationName, travelDate } = state

  return (
    <div className={styles.page}>
      <div className="container container--narrow">
        <button className={styles.backBtn} onClick={() => navigate(-1)}>← Back to seat map</button>

        <h1 className={styles.title}>Confirm your booking</h1>

        <div className={styles.layout}>
          {/* ── Passenger form ─────────────────────────────────────── */}
          <form className={styles.formCard} onSubmit={handleSubmit} noValidate>
            <h2 className={styles.sectionTitle}>Passenger details</h2>

            <div className={styles.fieldGroup}>
              <div className={styles.field}>
                <label className={styles.label} htmlFor="passengerName">Full name</label>
                <input
                  id="passengerName"
                  name="passengerName"
                  type="text"
                  className={styles.input}
                  value={form.passengerName}
                  onChange={handleChange}
                  placeholder="As on NIC / Passport"
                  required
                  minLength={2}
                  maxLength={100}
                />
              </div>

              <div className={styles.field}>
                <label className={styles.label} htmlFor="passengerEmail">Email address</label>
                <input
                  id="passengerEmail"
                  name="passengerEmail"
                  type="email"
                  className={styles.input}
                  value={form.passengerEmail}
                  onChange={handleChange}
                  placeholder="you@example.com"
                  required
                />
              </div>

              <div className={styles.field}>
                <label className={styles.label} htmlFor="passengerPhone">
                  Phone number <span className={styles.optional}>(optional)</span>
                </label>
                <input
                  id="passengerPhone"
                  name="passengerPhone"
                  type="tel"
                  className={styles.input}
                  value={form.passengerPhone}
                  onChange={handleChange}
                  placeholder="+94 7X XXX XXXX"
                />
              </div>
            </div>

            <button
              type="submit"
              className={styles.submitBtn}
              disabled={loading}
              id="confirm-booking-btn"
            >
              {loading ? 'Processing…' : 'Confirm and book seat'}
            </button>

            <p className={styles.holdNote}>
              Your seat will be held for 10 minutes once booked.
            </p>
          </form>

          {/* ── Booking summary ────────────────────────────────────── */}
          <div className={styles.summary}>
            <div className={styles.summaryCard}>
              <h2 className={styles.sectionTitle}>Trip summary</h2>

              <div className={styles.summaryRow}>
                <span>From</span>
                <strong>{fromStationName}</strong>
              </div>
              <div className={styles.summaryRow}>
                <span>To</span>
                <strong>{toStationName}</strong>
              </div>
              <div className={styles.summaryRow}>
                <span>Date</span>
                <strong>{travelDate}</strong>
              </div>
              <div className={styles.summaryRow}>
                <span>Coach</span>
                <strong>Coach {seat.coachNumber} · {seat.coachClass.replace('_', ' ')}</strong>
              </div>
              <div className={styles.summaryRow}>
                <span>Seat</span>
                <strong>{seat.seatNumber}</strong>
              </div>

              <div className={styles.divider}></div>

              {fareLoad ? (
                <div className={styles.fareLoading}>Calculating fare…</div>
              ) : fare ? (
                <>
                  <div className={styles.fareBreakdown}>
                    <div className={styles.fareRow}>
                      <span>Distance</span>
                      <span>{fare.distanceKm} km</span>
                    </div>
                    <div className={styles.fareRow}>
                      <span>Base rate</span>
                      <span>LKR {fare.baseRatePerKm}/km</span>
                    </div>
                    <div className={styles.fareRow}>
                      <span>Class ({fare.coachClass.replace('_', ' ')})</span>
                      <span>{fare.classMultiplier}×</span>
                    </div>
                    {fare.isPeak && (
                      <div className={styles.fareRow}>
                        <span>Weekend surcharge</span>
                        <span>{fare.peakMultiplier}×</span>
                      </div>
                    )}
                  </div>
                  <div className={styles.fareTotal}>
                    <span>Total fare</span>
                    <strong>LKR {Number(fare.totalFare).toFixed(2)}</strong>
                  </div>
                </>
              ) : null}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
