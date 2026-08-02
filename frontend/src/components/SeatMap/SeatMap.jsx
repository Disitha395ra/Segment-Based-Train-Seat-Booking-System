import styles from './SeatMap.module.css'

const CLASS_LABELS = {
  FIRST:            '1st Class',
  SECOND_RESERVED:  '2nd Reserved',
  THIRD_RESERVED:   '3rd Reserved',
}

const CLASS_COLORS = {
  FIRST:            '#1B3A6B',
  SECOND_RESERVED:  '#2b60a9',
  THIRD_RESERVED:   '#4a7ec4',
}

export default function SeatMap({ coaches, seats, selectedSeatIds = [], onSelectSeat, isLoading }) {
  if (isLoading) {
    return (
      <div className={styles.loading}>
        <div className={styles.loadingBar}></div>
        <div className={styles.loadingText}>Loading seat map…</div>
      </div>
    )
  }

  if (!seats || seats.length === 0) {
    return <div className={styles.empty}>No reserved seats available for this route.</div>
  }

  // Group seats by coachId
  const byCoachedId = {}
  for (const seat of seats) {
    if (!byCoachedId[seat.coachId]) byCoachedId[seat.coachId] = []
    byCoachedId[seat.coachId].push(seat)
  }

  // Build unique coach list from seats (maintaining coach order)
  const coachGroups = []
  const seen = new Set()
  for (const seat of seats) {
    if (!seen.has(seat.coachId)) {
      seen.add(seat.coachId)
      coachGroups.push({
        coachId:     seat.coachId,
        coachNumber: seat.coachNumber,
        coachClass:  seat.coachClass,
        seats:       byCoachedId[seat.coachId],
      })
    }
  }

  const totalSeats     = seats.length
  const availableSeats = seats.filter((s) => s.available).length

  return (
    <div className={styles.wrapper}>
      {/* Legend */}
      <div className={styles.legend}>
        <div className={styles.legendItem}>
          <span className={`${styles.legendDot} ${styles.dotAvailable}`}></span>
          Available ({availableSeats})
        </div>
        <div className={styles.legendItem}>
          <span className={`${styles.legendDot} ${styles.dotBooked}`}></span>
          Booked ({totalSeats - availableSeats})
        </div>
        <div className={styles.legendItem}>
          <span className={`${styles.legendDot} ${styles.dotSelected}`}></span>
          Selected
        </div>
        {selectedSeatIds.length > 0 && (
          <div className={styles.selectedInfo}>
            {selectedSeatIds.length} seat(s) selected — max 6 allowed
          </div>
        )}
      </div>

      {/* Train diagram */}
      <div className={styles.trainContainer}>
        {/* Engine indicator */}
        <div className={styles.engineLabel}>← Engine (Colombo Fort direction)</div>

        {/* Coaches */}
        <div className={styles.coaches}>
          {coachGroups.map((coach) => (
            <div key={coach.coachId} className={styles.coach}>
              {/* Coach header */}
              <div
                className={styles.coachHeader}
                style={{ background: CLASS_COLORS[coach.coachClass] }}
              >
                <span className={styles.coachNumber}>Coach {coach.coachNumber}</span>
                <span className={styles.coachClass}>{CLASS_LABELS[coach.coachClass]}</span>
              </div>

              {/* Seat grid — 2+2 arrangement */}
              <div className={styles.seatGrid}>
                {coach.seats.map((seat) => {
                  const isSelected  = selectedSeatIds.includes(seat.id)
                  const isAvailable = seat.available
                  return (
                    <button
                      key={seat.id}
                      className={`${styles.seat} ${
                        isSelected  ? styles.seatSelected  :
                        isAvailable ? styles.seatAvailable :
                                      styles.seatBooked
                      }`}
                      onClick={() => isAvailable && onSelectSeat(seat)}
                      disabled={!isAvailable}
                      title={
                        isSelected  ? `Seat ${seat.seatNumber} — Selected (Click to unselect)` :
                        isAvailable ? `Seat ${seat.seatNumber} — Click to select` :
                                      `Seat ${seat.seatNumber} — Booked`
                      }
                      aria-label={`Seat ${seat.seatNumber}, ${isAvailable ? 'available' : 'booked'}`}
                      aria-pressed={isSelected}
                    >
                      {seat.seatNumber}
                      {seat.waitlistCount > 0 && !isSelected && isAvailable && (
                        <span className={styles.waitlistDot} title={`${seat.waitlistCount} on waitlist`}>
                          {seat.waitlistCount}
                        </span>
                      )}
                    </button>
                  )
                })}
              </div>

              {/* Coach stats */}
              <div className={styles.coachStats}>
                {coach.seats.filter((s) => s.available).length} / {coach.seats.length} free
              </div>
            </div>
          ))}
        </div>

        <div className={styles.engineLabel} style={{ textAlign: 'right' }}>
          Badulla direction →
        </div>
      </div>

      {/* Refresh notice */}
      <p className={styles.refreshNote}>
        Availability refreshes every 10 seconds. Seats are held for 10 minutes after booking.
      </p>
    </div>
  )
}
