import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { stationsApi, trainsApi } from '../api/endpoints'
import { useToast } from '../components/common/Toast/ToastContext'
import styles from './HomePage.module.css'

export default function HomePage() {
  const navigate = useNavigate()
  const toast = useToast()

  const [stations, setStations] = useState([])
  const [trains,   setTrains]   = useState([])
  const [loading,  setLoading]  = useState(true)

  const now = new Date()
  // Adjust to local timezone format YYYY-MM-DD
  const offset = now.getTimezoneOffset() * 60000
  const localToday = new Date(now.getTime() - offset)
  const today = localToday.toISOString().split('T')[0]
  
  const maxTime = new Date(now.getTime() + 90 * 86400000 - offset)
  const maxDate = maxTime.toISOString().split('T')[0]

  const [form, setForm] = useState({
    trainId:       '',
    fromStationId: '',
    toStationId:   '',
    travelDate:    today,
  })

  useEffect(() => {
    Promise.all([stationsApi.list(), trainsApi.list()])
      .then(([stRes, trRes]) => {
        setStations(stRes.data)
        setTrains(trRes.data)
        if (trRes.data.length > 0) {
          setForm((f) => ({ ...f, trainId: trRes.data[0].id }))
        }
      })
      .catch(() => toast('Failed to load route data', 'error'))
      .finally(() => setLoading(false))
  }, [])

  const fromStation = stations.find((s) => s.id === form.fromStationId)
  // Filter "to" stations to only those after "from" on the route
  const toStations = fromStation
    ? stations.filter((s) => s.orderIndex > fromStation.orderIndex)
    : []

  const handleChange = (e) => {
    const { name, value } = e.target
    setForm((f) => {
      const next = { ...f, [name]: value }
      // Clear "to" if "from" changes and "to" is now invalid
      if (name === 'fromStationId') {
        const fromIdx = stations.find((s) => s.id === value)?.orderIndex ?? -1
        const toIdx   = stations.find((s) => s.id === f.toStationId)?.orderIndex ?? -1
        if (toIdx <= fromIdx) next.toStationId = ''
      }
      return next
    })
  }

  const handleSearch = (e) => {
    e.preventDefault()
    if (!form.fromStationId || !form.toStationId || !form.travelDate || !form.trainId) {
      toast('Please fill in all fields', 'warning')
      return
    }
    navigate('/seats', { state: { ...form } })
  }

  if (loading) {
    return (
      <div className={styles.page}>
        <div className={styles.hero}>
          <h1 className={styles.heroTitle}>Loading route information…</h1>
        </div>
      </div>
    )
  }

  return (
    <div className={styles.page}>
      {/* ── Hero ──────────────────────────────────────────────────────────── */}
      <section className={styles.hero}>
        <div className={styles.heroContent}>
          <div className={styles.routeBadge}>Colombo Fort → Badulla · 292 km</div>
          <h1 className={styles.heroTitle}>Reserve your seat,<br />for any leg of the journey</h1>
          <p className={styles.heroSub}>
            Book a reserved seat only for the distance you travel.
            One seat, multiple passengers — each paying only their share.
          </p>
        </div>
      </section>

      {/* ── Search form ───────────────────────────────────────────────────── */}
      <div className={styles.searchWrapper}>
        <form className={styles.searchCard} onSubmit={handleSearch} noValidate>
          <h2 className={styles.searchTitle}>Find available seats</h2>

          <div className={styles.formGrid}>
            {/* Train */}
            <div className={styles.field}>
              <label className={styles.label} htmlFor="trainId">Train</label>
              <select
                id="trainId"
                name="trainId"
                className={styles.select}
                value={form.trainId}
                onChange={handleChange}
                required
              >
                <option value="">Select train…</option>
                {trains.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name} ({t.trainNumber}) — departs {t.departureTime}
                  </option>
                ))}
              </select>
            </div>

            {/* From */}
            <div className={styles.field}>
              <label className={styles.label} htmlFor="fromStationId">From</label>
              <select
                id="fromStationId"
                name="fromStationId"
                className={styles.select}
                value={form.fromStationId}
                onChange={handleChange}
                required
              >
                <option value="">Select origin…</option>
                {stations.map((s) => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </select>
            </div>

            {/* To */}
            <div className={styles.field}>
              <label className={styles.label} htmlFor="toStationId">To</label>
              <select
                id="toStationId"
                name="toStationId"
                className={styles.select}
                value={form.toStationId}
                onChange={handleChange}
                disabled={!form.fromStationId}
                required
              >
                <option value="">Select destination…</option>
                {toStations.map((s) => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </select>
              {form.fromStationId && toStations.length === 0 && (
                <span className={styles.fieldHint}>No onward stations available</span>
              )}
            </div>

            {/* Date */}
            <div className={styles.field}>
              <label className={styles.label} htmlFor="travelDate">Travel Date</label>
              <input
                id="travelDate"
                name="travelDate"
                type="date"
                className={styles.input}
                value={form.travelDate}
                min={today}
                max={maxDate}
                onChange={handleChange}
                required
              />
            </div>
          </div>

          {/* Route preview */}
          {form.fromStationId && form.toStationId && (() => {
            const f = stations.find((s) => s.id === form.fromStationId)
            const t = stations.find((s) => s.id === form.toStationId)
            const dist = t && f ? (t.distanceKm - f.distanceKm).toFixed(1) : null
            return (
              <div className={styles.routePreview}>
                <span>{f?.name}</span>
                <span className={styles.routeArrow}>→</span>
                <span>{t?.name}</span>
                {dist && <span className={styles.routeDist}>{dist} km</span>}
              </div>
            )
          })()}

          <button type="submit" className={styles.searchBtn} id="search-seats-btn">
            Show available seats
          </button>
        </form>
      </div>

      {/* ── How it works ──────────────────────────────────────────────────── */}
      <section className={styles.howItWorks}>
        <div className="container">
          <h2 className={styles.howTitle}>How segment booking works</h2>
          <div className={styles.steps}>
            {[
              { step: '01', title: 'Choose your leg', body: 'Select any two stations on the route — you only pay for the distance you actually travel.' },
              { step: '02', title: 'Pick a seat',     body: 'See the real-time seat map. Green seats are free for your exact segment. Partially-booked seats are shown clearly.' },
              { step: '03', title: 'Book & travel',   body: 'Confirm your details. The seat is held for 10 minutes. Another passenger can book the same seat for a different leg.' },
            ].map((s) => (
              <div key={s.step} className={styles.step}>
                <span className={styles.stepNum}>{s.step}</span>
                <h3 className={styles.stepTitle}>{s.title}</h3>
                <p className={styles.stepBody}>{s.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </div>
  )
}
