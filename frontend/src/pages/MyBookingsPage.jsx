import { useState, useEffect } from 'react'
import { bookingsApi } from '../api/endpoints'
import { useToast } from '../components/common/Toast/ToastContext'
import styles from './MyBookingsPage.module.css'

const STATUS_MAP = {
  CONFIRMED: { label: 'Confirmed', cls: 'success' },
  HELD:      { label: 'Held',      cls: 'warning' },
  CANCELLED: { label: 'Cancelled', cls: 'error'   },
  EXPIRED:   { label: 'Expired',   cls: 'error'   },
}

export default function MyBookingsPage() {
  const toast = useToast()
  const [bookings, setBookings]   = useState([])
  const [loading,  setLoading]    = useState(true)
  const [page,     setPage]       = useState(1)
  const [meta,     setMeta]       = useState(null)
  const [cancelling, setCancelling] = useState(null)

  const load = async (p = 1) => {
    setLoading(true)
    try {
      const res = await bookingsApi.list(p, 10)
      setBookings(res.data)
      setMeta(res.meta?.pagination)
    } catch {
      toast('Failed to load bookings', 'error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load(page) }, [page])

  const handleCancel = async (id) => {
    if (!confirm('Cancel this booking?')) return
    setCancelling(id)
    try {
      await bookingsApi.cancel(id)
      toast('Booking cancelled', 'info')
      load(page)
    } catch (err) {
      toast(err.message || 'Failed to cancel', 'error')
    } finally {
      setCancelling(null)
    }
  }

  return (
    <div className={styles.page}>
      <div className="container">
        <div className="page-header">
          <h1 className="page-header__title">My bookings</h1>
          <p className="page-header__subtitle">Your seat reservations on the Colombo Fort – Badulla line</p>
        </div>

        {loading ? (
          <div className={styles.loading}>Loading…</div>
        ) : bookings.length === 0 ? (
          <div className={styles.empty}>
            <p>No bookings yet.</p>
            <a href="/" className={styles.bookLink}>Book a seat →</a>
          </div>
        ) : (
          <>
            <div className={styles.list}>
              {bookings.map((b) => {
                const st = STATUS_MAP[b.status] ?? { label: b.status, cls: 'info' }
                const canCancel = b.status === 'HELD' || b.status === 'CONFIRMED'
                return (
                  <div key={b.id} className={styles.bookingCard}>
                    <div className={styles.cardTop}>
                      <div>
                        <span className={styles.refCode}>{b.referenceCode}</span>
                        <span className={`badge badge--${st.cls}`} style={{ marginLeft: 8 }}>
                          {st.label}
                        </span>
                      </div>
                      <span className={styles.date}>{b.travelDate}</span>
                    </div>

                    <div className={styles.cardBody}>
                      <div className={styles.infoRow}>
                        <span className={styles.infoLabel}>Passenger</span>
                        <span>{b.passengerName}</span>
                      </div>
                      <div className={styles.infoRow}>
                        <span className={styles.infoLabel}>Fare</span>
                        <span className={styles.fare}>LKR {Number(b.fareAmount).toFixed(2)}</span>
                      </div>
                      <div className={styles.infoRow}>
                        <span className={styles.infoLabel}>Booked</span>
                        <span>{new Date(b.createdAt).toLocaleString()}</span>
                      </div>
                      {b.heldUntil && b.status === 'HELD' && (
                        <div className={styles.infoRow}>
                          <span className={styles.infoLabel}>Held until</span>
                          <span className={styles.held}>{new Date(b.heldUntil).toLocaleTimeString()}</span>
                        </div>
                      )}
                    </div>

                    {canCancel && (
                      <div className={styles.cardFooter}>
                        <button
                          className={styles.cancelBtn}
                          onClick={() => handleCancel(b.id)}
                          disabled={cancelling === b.id}
                        >
                          {cancelling === b.id ? 'Cancelling…' : 'Cancel booking'}
                        </button>
                      </div>
                    )}
                  </div>
                )
              })}
            </div>

            {/* Pagination */}
            {meta && meta.totalPages > 1 && (
              <div className={styles.pagination}>
                <button
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page === 1}
                  className={styles.pageBtn}
                >
                  ← Previous
                </button>
                <span className={styles.pageInfo}>Page {page} of {meta.totalPages}</span>
                <button
                  onClick={() => setPage((p) => Math.min(meta.totalPages, p + 1))}
                  disabled={page === meta.totalPages}
                  className={styles.pageBtn}
                >
                  Next →
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
