import { useLocation, Link, useNavigate } from 'react-router-dom'
import { QRCodeCanvas } from 'qrcode.react'
import styles from './ConfirmationPage.module.css'

export default function ConfirmationPage() {
  const { state } = useLocation()
  const navigate  = useNavigate()

  if (!state?.booking) {
    navigate('/', { replace: true })
    return null
  }

  const { booking, selectedSeats, fromStationName, toStationName, fare } = state

  const qrData = JSON.stringify({
    ref: booking.referenceCode,
    passenger: booking.passengerName,
    route: `${fromStationName} to ${toStationName}`,
    date: booking.travelDate,
    seats: selectedSeats.map(s => `C${s.coachNumber}-${s.seatNumber}`).join(','),
    status: 'PAID'
  })

  return (
    <div className={styles.page}>
      <div className="container container--narrow">
        <div className={styles.ticket}>
          
          <div className={styles.ticketTop}>
            <div className={styles.checkmark}>✓</div>
            <h1 className={styles.title}>Payment Successful!</h1>
            <p className={styles.subtitle}>Your seat is confirmed. Have a safe journey.</p>
            
            <div className={styles.refBox}>
              <span className={styles.refLabel}>Booking reference</span>
              <span className={styles.refCode}>{booking.referenceCode}</span>
            </div>
          </div>

          <div className={styles.ticketDivider}></div>

          <div className={styles.ticketBottom}>
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
                  <span>Total Paid</span>
                  <strong className={styles.fare}>LKR {Number(fare.totalFare).toFixed(2)}</strong>
                </div>
              )}
            </div>

            <div className={styles.qrSection}>
              <p className={styles.qrNote}>Scan for digital ticket</p>
              <div className={styles.qrCodeWrapper}>
                <QRCodeCanvas 
                  value={qrData} 
                  size={140} 
                  level={"H"} 
                  includeMargin={true}
                />
              </div>
            </div>

            <p className={styles.segmentNote}>
              This ticket covers only your booked segment ({fromStationName} → {toStationName}).
              Show this QR code to the conductor upon request.
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
    </div>
  )
}
