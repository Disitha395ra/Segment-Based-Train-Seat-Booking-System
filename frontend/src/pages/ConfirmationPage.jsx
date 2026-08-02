import { useLocation, Link, useNavigate } from 'react-router-dom'
import styles from './ConfirmationPage.module.css'

export default function ConfirmationPage() {
  const { state } = useLocation()
  const navigate  = useNavigate()

  if (!state?.booking) {
    navigate('/', { replace: true })
    return null
  }

  const { booking, selectedSeats, fromStationName, toStationName, fare } = state

  return (
    <div className={styles.page}>
      <div className="container container--narrow">
        <div className={styles.card}>
          <div className={styles.checkmark}>✓</div>
          <h1 className={styles.title}>Booking confirmed</h1>
          <p className={styles.subtitle}>Your seat is reserved. Show this reference at the station.</p>

          <div className={styles.refBox}>
            <span className={styles.refLabel}>Booking reference</span>
            <span className={styles.refCode}>{booking.referenceCode}</span>
          </div>

          <div className={styles.details}>
            <div className={styles.detailRow}>
              <span>Passenger</span>
              <strong>{booking.passengerName}</strong>
            </div>
            <div className={styles.detailRow}>
              <span>From</span>
              <strong>{fromStationName}</strong>
            </div>
            <div className={styles.detailRow}>
              <span>To</span>
              <strong>{toStationName}</strong>
            </div>
            <div className={styles.detailRow}>
              <span>Travel date</span>
              <strong>{booking.travelDate}</strong>
            </div>
            <div className={styles.detailRow}>
              <span>Class</span>
              <strong>{selectedSeats[0].coachClass.replace('_', ' ')}</strong>
            </div>
            <div className={styles.detailRow}>
              <span>Seats ({selectedSeats.length})</span>
              <strong style={{ textAlign: 'right' }}>
                {selectedSeats.map(s => `C${s.coachNumber}-${s.seatNumber}`).join(', ')}
              </strong>
            </div>
            {fare && (
              <div className={styles.detailRow}>
                <span>Fare paid</span>
                <strong className={styles.fare}>LKR {Number(fare.totalFare).toFixed(2)}</strong>
              </div>
            )}
          </div>

          <p className={styles.segmentNote}>
            This ticket covers only your booked segment ({fromStationName} → {toStationName}).
            Another passenger may be using this seat for a different leg of the journey.
          </p>

          <div className={styles.actions}>
            <Link to="/" className={styles.newBookingBtn}>Book another seat</Link>
            {localStorage.getItem('accessToken') && (
              <Link to="/my-bookings" className={styles.viewBookingsBtn}>View my bookings</Link>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
