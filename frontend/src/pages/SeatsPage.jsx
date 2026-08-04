import { useState, useEffect, useCallback, useRef } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { trainsApi, stationsApi, waitlistApi } from '../api/endpoints'
import SeatMap from '../components/SeatMap/SeatMap'
import { useToast } from '../components/common/Toast/ToastContext'
import styles from './SeatsPage.module.css'

const POLL_INTERVAL = 10000 // 10 seconds

export default function SeatsPage() {
  const { state } = useLocation()
  const navigate  = useNavigate()
  const toast     = useToast()

  const [seats,         setSeats]         = useState([])
  const [fromStation,   setFromStation]   = useState(null)
  const [toStation,     setToStation]     = useState(null)
  const [selectedSeats, setSelectedSeats] = useState([])
  const [loading,       setLoading]       = useState(true)
  const [conflictSeatIds, setConflictSeatIds] = useState([]) // real-time conflict detection
  const [showWaitlist,  setShowWaitlist]  = useState(false)
  const [wlEmail,       setWlEmail]       = useState('')
  const [wlName,        setWlName]        = useState('')

  const pollRef = useRef(null)
  const prevAvailRef = useRef({}) // track previous availability for conflict detection

  const fetchSeats = useCallback(async () => {
    if (!state) return
    try {
      const res = await trainsApi.seatAvailability(
        state.trainId, state.fromStationId, state.toStationId, state.travelDate
      )
      const newSeats = res.data

      // Conflict detection: if any selected seat just became unavailable, warn the user
      if (selectedSeats.length > 0) {
        const newlyUnavailable = []
        selectedSeats.forEach(selSeat => {
          const updatedSeat = newSeats.find((s) => s.id === selSeat.id)
          if (updatedSeat && !updatedSeat.available && prevAvailRef.current[selSeat.id]) {
            newlyUnavailable.push(selSeat.id)
          }
        })

        if (newlyUnavailable.length > 0) {
          toast('One or more of your selected seats just became unavailable — please choose others.', 'error', 6000)
          setConflictSeatIds(newlyUnavailable)
          setSelectedSeats(prev => prev.filter(s => !newlyUnavailable.includes(s.id)))
        }
      }

      // Update prev availability map
      const newAvail = {}
      newSeats.forEach((s) => { newAvail[s.id] = s.available })
      prevAvailRef.current = newAvail

      setSeats(newSeats)
    } catch {
      // Silent poll failure — don't disrupt the user
    } finally {
      setLoading(false)
    }
  }, [state, selectedSeats, toast])

  useEffect(() => {
    if (!state) {
      navigate('/', { replace: true })
      return
    }
    // Fetch station names
    Promise.all([stationsApi.list()]).then(([stRes]) => {
      const stations = stRes.data
      setFromStation(stations.find((s) => s.id === state.fromStationId))
      setToStation(stations.find((s) => s.id === state.toStationId))
    })

    fetchSeats()
    pollRef.current = setInterval(fetchSeats, POLL_INTERVAL)
    return () => clearInterval(pollRef.current)
  }, [state, navigate, fetchSeats])

  const handleSelectSeat = (seat) => {
    setConflictSeatIds([])
    setSelectedSeats(prev => {
      // Toggle off if already selected
      if (prev.find(s => s.id === seat.id)) {
        return prev.filter(s => s.id !== seat.id)
      }
      // Enforce max limit of 6
      if (prev.length >= 6) {
        toast('You can only select up to 6 seats at once.', 'warning')
        return prev
      }
      return [...prev, seat]
    })
  }

  const handleBook = () => {
    if (selectedSeats.length === 0) return
    navigate('/book', {
      state: {
        ...state,
        seatIds: selectedSeats.map(s => s.id),
        selectedSeats: selectedSeats,
        fromStationName: fromStation?.name,
        toStationName:   toStation?.name,
      },
    })
  }

  const handleJoinWaitlist = async (e) => {
    e.preventDefault()
    if (!wlEmail || !wlName) return
    try {
      await waitlistApi.join({
        seatId:          selectedSeat?.id ?? seats[0]?.id,
        fromStationId:   state.fromStationId,
        toStationId:     state.toStationId,
        travelDate:      state.travelDate,
        passengerName:   wlName,
        passengerEmail:  wlEmail,
      })
      toast('Added to waitlist — we\'ll notify you if a seat opens', 'success')
      setShowWaitlist(false)
    } catch (err) {
      toast(err.message || 'Failed to join waitlist', 'error')
    }
  }

  const availableCount = seats.filter((s) => s.available).length

  return (
    <div className={styles.page}>
      <div className="container">
        {/* ── Header ──────────────────────────────────────────────────────── */}
        <div className={styles.header}>
          <button className={styles.backBtn} onClick={() => navigate('/')}>← Back</button>
          <div className={styles.tripInfo}>
            <h1 className={styles.tripTitle}>
              {fromStation?.name ?? '…'} → {toStation?.name ?? '…'}
            </h1>
            <p className={styles.tripMeta}>
              {state?.travelDate} · {availableCount} seat{availableCount !== 1 ? 's' : ''} available
            </p>
          </div>

          {/* Real-time indicator */}
          <div className={styles.liveIndicator}>
            <span className={styles.liveDot}></span>
            Live
          </div>
        </div>

        <div className={styles.layout}>
          {/* ── Seat Map ───────────────────────────────────────────────── */}
          <div className={styles.mapSection}>
            <SeatMap
              seats={seats}
              selectedSeatIds={selectedSeats.map(s => s.id)}
              onSelectSeat={handleSelectSeat}
              isLoading={loading}
            />

            {/* Conflict warning */}
            {conflictSeatIds.length > 0 && (
              <div className={styles.conflictBanner}>
                One or more seats you had selected were just booked by another passenger.
                Please choose different seats.
              </div>
            )}
          </div>

          {/* ── Booking sidebar ────────────────────────────────────────── */}
          <div className={styles.sidebar}>
            <div className={styles.sideCard}>
              <h2 className={styles.sideTitle}>Your journey</h2>

              <div className={styles.routeBlock}>
                <div className={styles.routeRow}>
                  <span className={styles.routeLabel}>From</span>
                  <span className={styles.routeValue}>{fromStation?.name}</span>
                </div>
                <div className={styles.routeLine}></div>
                <div className={styles.routeRow}>
                  <span className={styles.routeLabel}>To</span>
                  <span className={styles.routeValue}>{toStation?.name}</span>
                </div>
                <div className={styles.routeRow}>
                  <span className={styles.routeLabel}>Date</span>
                  <span className={styles.routeValue}>{state?.travelDate}</span>
                </div>
              </div>

              {selectedSeats.length > 0 ? (
                <div className={styles.selectedBlock}>
                  <div className={styles.selectedBadge}>{selectedSeats.length} seat(s) selected</div>
                  <div className={styles.selectedDetail}>
                    {selectedSeats.map(s => (
                      <div key={s.id} style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                        <span>Coach {s.coachNumber} · Seat {s.seatNumber}</span>
                        <span className={styles.coachClassTag}>{s.coachClass.replace('_', ' ')}</span>
                      </div>
                    ))}
                  </div>
                  <button
                    className={styles.bookBtn}
                    onClick={handleBook}
                    id="proceed-to-book-btn"
                  >
                    Continue to booking
                  </button>
                  <button
                    className={styles.clearBtn}
                    onClick={() => setSelectedSeats([])}
                  >
                    Clear selection
                  </button>
                </div>
              ) : (
                <p className={styles.selectHint}>
                  Select an available seat from the map to continue.
                </p>
              )}

              {availableCount === 0 && !loading && (
                <div className={styles.fullyBooked}>
                  <p>All seats are booked for this segment.</p>
                  <button
                    className={styles.waitlistBtn}
                    onClick={() => setShowWaitlist(true)}
                  >
                    Join waitlist
                  </button>
                </div>
              )}
            </div>

            {/* ── Waitlist form ─────────────────────────────────────── */}
            {showWaitlist && (
              <div className={styles.sideCard}>
                <h3 className={styles.sideTitle}>Join waitlist</h3>
                <p style={{ fontSize: 'var(--font-size-sm)', color: 'var(--color-neutral-500)', marginBottom: 'var(--space-4)' }}>
                  We'll notify you by email if a seat becomes available for this segment.
                </p>
                <form onSubmit={handleJoinWaitlist}>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
                    <input
                      type="text"
                      placeholder="Your name"
                      value={wlName}
                      onChange={(e) => setWlName(e.target.value)}
                      required
                      className={styles.wlInput}
                    />
                    <input
                      type="email"
                      placeholder="Email address"
                      value={wlEmail}
                      onChange={(e) => setWlEmail(e.target.value)}
                      required
                      className={styles.wlInput}
                    />
                    <button type="submit" className={styles.bookBtn}>
                      Join waitlist
                    </button>
                  </div>
                </form>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
